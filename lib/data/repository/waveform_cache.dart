import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../model/track.dart';
import 'ng_repository.dart';

/// One owner for the current track's waveform: HTML lookup, PNG on disk and
/// decoded image. Playback starts preparation; player widgets share that work.
class WaveformImageCache {
  WaveformImageCache({
    Future<Directory> Function()? cacheDirectory,
    Future<String?> Function(Track track, bool refresh)? resolveUrl,
    Future<Uint8List> Function(String url)? download,
    Duration retryDelay = const Duration(seconds: 1),
  })  : _cacheDirectory = cacheDirectory ?? _defaultDirectory,
        _resolveUrl = resolveUrl ?? _defaultResolveUrl,
        _download = download ?? _defaultDownload,
        _retryDelay = retryDelay;

  static final WaveformImageCache instance = WaveformImageCache();

  final Future<Directory> Function() _cacheDirectory;
  final Future<String?> Function(Track, bool) _resolveUrl;
  final Future<Uint8List> Function(String) _download;
  final Duration _retryDelay;

  String? _currentTrackId;
  int _generation = 0;
  ui.Image? _image;
  Future<void>? _pending;
  // All disk operations are ordered. An old cleanup or partial write cannot
  // delete/overwrite the new track's file, including when switching A -> B -> A.
  Future<void> _diskTail = Future<void>.value();

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory(path.join(root.path, 'waveform_cache'));
  }

  static Future<String?> _defaultResolveUrl(Track track, bool refresh) =>
      NgRepository().getWaveformUrl(track, refresh: refresh);

  static Future<Uint8List> _defaultDownload(String url) async {
    final response = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'image/png,image/*',
      'Referer': 'https://www.newgrounds.com/',
    }).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw HttpException('Waveform HTTP ${response.statusCode}',
          uri: Uri.parse(url));
    }
    return response.bodyBytes;
  }

  bool _isCurrent(int generation) => generation == _generation;

  /// Identifies the current selection, including A -> B -> A between frames.
  int get revision => _generation;

  /// Selects a track and starts loading even if the full-screen player is shut
  /// or the audio is already cached locally. Does not delay audio playback.
  Future<void> prepare(Track track) {
    if (_currentTrackId != track.id) {
      _generation++;
      _currentTrackId = track.id;
      _pending = null;
      _image?.dispose();
      _image = null;
    }
    return _ensureLoaded(track);
  }

  /// The caller owns this handle; disposing it never invalidates the cache.
  ui.Image? known(String trackId) =>
      _currentTrackId == trackId ? _image?.clone() : null;

  Future<ui.Image?> load(Track track) async {
    if (_currentTrackId == null) {
      // Also permits use before the playback controller has been attached.
      unawaited(prepare(track));
    }
    if (_currentTrackId != track.id) return null;
    final generation = _generation;
    await _ensureLoaded(track);
    return _isCurrent(generation) ? known(track.id) : null;
  }

  Future<void> _ensureLoaded(Track track) {
    if (_image != null) return Future<void>.value();
    final generation = _generation;
    return _pending ??= _load(track, generation).whenComplete(() {
      if (_isCurrent(generation)) _pending = null;
    });
  }

  Future<T> _onDisk<T>(Future<T> Function() operation) {
    final result = _diskTail.then((_) => operation());
    _diskTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _prune(Directory dir, String? keep, int generation) async {
    await for (final entity in dir.list()) {
      if (!_isCurrent(generation)) return;
      if (entity is File && entity.path != keep) await entity.delete();
    }
  }

  Future<Uint8List?> _readCached(Track track, int generation) =>
      _onDisk(() async {
        if (!_isCurrent(generation)) return null;
        final dir = await _cacheDirectory();
        await dir.create(recursive: true);
        if (!_isCurrent(generation)) return null;
        final file = File(path.join(dir.path, '${track.id}.png'));
        await _prune(dir, file.path, generation);
        if (!_isCurrent(generation) || !await file.exists()) return null;
        return file.readAsBytes();
      });

  Future<void> _writeCached(Track track, Uint8List bytes, int generation) =>
      _onDisk(() async {
        if (!_isCurrent(generation)) return;
        final dir = await _cacheDirectory();
        await dir.create(recursive: true);
        if (!_isCurrent(generation)) return;
        final file = File(path.join(dir.path, '${track.id}.png'));
        final partial = File('${file.path}.part');
        try {
          await partial.writeAsBytes(bytes, flush: true);
          if (!_isCurrent(generation)) return;
          await partial.rename(file.path);
          await _prune(dir, file.path, generation);
        } finally {
          if (await partial.exists()) await partial.delete();
        }
      });

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  bool _store(ui.Image image, int generation) {
    if (!_isCurrent(generation)) {
      image.dispose();
      return false;
    }
    _image?.dispose();
    _image = image;
    return true;
  }

  Future<void> _load(Track track, int generation) async {
    try {
      final bytes = await _readCached(track, generation);
      if (!_isCurrent(generation)) return;
      if (bytes != null) {
        _store(await _decode(bytes), generation);
        return;
      }
    } catch (error) {
      debugPrint('[waveform] ${track.id}: disk cache unavailable: $error');
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_isCurrent(generation)) return;
      try {
        final url = await _resolveUrl(track, attempt > 0);
        if (!_isCurrent(generation)) return;
        if (url == null || url.isEmpty) {
          // A valid listen page without peaks is not a transient PNG failure.
          return;
        }
        final bytes = await _download(url);
        if (!_isCurrent(generation)) return;
        if (!_store(await _decode(bytes), generation)) return;
        // Decode before saving: an HTML error page or broken PNG must never
        // become a persistent cache hit. Disk failure still leaves RAM usable.
        try {
          await _writeCached(track, bytes, generation);
        } catch (error) {
          debugPrint('[waveform] ${track.id}: could not save PNG: $error');
        }
        return;
      } catch (error) {
        debugPrint('[waveform] ${track.id}: attempt ${attempt + 1}: $error');
        if (attempt < 2 && _isCurrent(generation)) {
          await Future<void>.delayed(_retryDelay * (attempt + 1));
        }
      }
    }
  }

  /// Invalidate outstanding requests and release the cache's image handle.
  /// The disk file remains available for the next app launch.
  void dispose() {
    _generation++;
    _currentTrackId = null;
    _pending = null;
    _image?.dispose();
    _image = null;
  }
}
