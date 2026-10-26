import 'dart:io';
import 'dart:ui' as ui;

import '../model/track.dart';
import 'cache_manager.dart';

/// Holds the decoded waveform peaks for the current track only. Reopening the
/// player for that track paints the waveform on the first frame; moving to
/// another track drops the old image.
class WaveformImageCache {
  WaveformImageCache._();

  static final WaveformImageCache instance = WaveformImageCache._();

  String? _currentTrackId;
  String? _trackId;
  ui.Image? _image;
  final Map<String, Future<void>> _loads = {};

  /// Returns a private handle to the current track's decoded image, or `null`
  /// when it is not cached. The caller owns and must dispose the handle.
  ui.Image? known(String trackId) {
    if (_trackId != trackId) return null;
    return _image?.clone();
  }

  /// Drops the decoded image when playback moves to another track.
  void keepOnly(String trackId) {
    if (_currentTrackId == trackId) return;
    _currentTrackId = trackId;
    _image?.dispose();
    _image = null;
    _trackId = null;
  }

  /// Loads (or reuses) the decoded peaks for [track]. Each caller receives its
  /// own handle, so disposing a widget's image never invalidates the cache.
  Future<ui.Image?> load(Track track) {
    final cached = known(track.id);
    if (cached != null) return Future.value(cached);

    final pending = _loads[track.id];
    if (pending != null) {
      return pending.then((_) => known(track.id));
    }

    final future = _load(track).whenComplete(() {
      _loads.remove(track.id);
    });
    _loads[track.id] = future;
    return future.then((_) => known(track.id));
  }

  Future<void> _load(Track track) async {
    try {
      final path = await CacheManager.instance.getWaveformPath(track);
      if (path == null) return;
      // Playback may have moved on while the PNG was being fetched.
      if (_currentTrackId != null && _currentTrackId != track.id) return;
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      _store(track.id, frame.image);
    } catch (_) {}
  }

  void _store(String trackId, ui.Image image) {
    // A newer track may have become current while this image was decoding.
    if (_currentTrackId != null && _currentTrackId != trackId) {
      image.dispose();
      return;
    }
    _image?.dispose();
    _trackId = trackId;
    _image = image;
  }
}
