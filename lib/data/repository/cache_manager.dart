import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../model/track.dart';
import 'local_db.dart';

class CacheManager {
  static CacheManager? _instance;
  static CacheManager get instance => _instance ??= CacheManager._();
  CacheManager._();

  final _db = LocalDb.instance;

  /// Get cache directory
  Future<Directory> getCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(path.join(appDir.path, 'track_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Check if track is cached
  Future<bool> isCached(String trackId) async {
    final d = await _db.db;
    final result = await d.query(
      'cached_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (result.isEmpty) return false;
    return File(result.first['local_path'] as String).exists();
  }

  /// Get local path for cached track
  Future<String?> getCachedPath(String trackId) async {
    final d = await _db.db;
    final result = await d.query(
      'cached_tracks',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final localPath = result.first['local_path'] as String;
    return await File(localPath).exists() ? localPath : null;
  }

  static bool _isLocalPath(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('file:')) return true;
    if (value.contains('://')) return false;
    return value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  static String _plainPath(String value) {
    if (!value.startsWith('file:')) return value;
    var plain = value.substring('file:'.length);
    if (plain.startsWith('//')) plain = plain.substring(2);
    return Uri.decodeComponent(plain);
  }

  /// Local full-size artwork for a cached track, whichever edition saved it.
  Future<String?> getCachedArtworkPath(String trackId) async {
    final d = await _db.db;
    final rows = await d.query(
      'cached_tracks',
      columns: ['icon_url'],
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    final icon = rows.isEmpty ? '' : (rows.first['icon_url'] as String? ?? '');
    final cacheDir = await getCacheDir();
    for (final ext in ['webp', 'jpg', 'png']) {
      final file = File(path.join(cacheDir.path, '${trackId}_art.$ext'));
      if (await file.exists()) return file.path;
    }
    if (_isLocalPath(icon)) {
      final plain = _plainPath(icon);
      if (await File(plain).exists()) return plain;
    }
    return null;
  }

  /// Local reduced-size artwork, used by the mini player and compact lists.
  Future<String?> getCachedIconPath(String trackId) async {
    final cacheDir = await getCacheDir();
    for (final ext in ['webp', 'jpg', 'png']) {
      final file = File(path.join(cacheDir.path, '${trackId}_icon.$ext'));
      if (await file.exists()) return file.path;
    }
    final d = await _db.db;
    final rows = await d.query(
      'cached_tracks',
      columns: ['icon_url'],
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final icon = rows.first['icon_url'] as String? ?? '';
      if (_isLocalPath(icon)) {
        final plain = _plainPath(icon);
        if (await File(plain).exists()) return plain;
      }
    }
    return null;
  }

  /// Persist recommendation/listing art without downloading or pinning audio.
  Future<String?> cacheTrackIcon(Track track) async {
    final cacheDir = await getCacheDir();
    return _cacheIcon(track, cacheDir);
  }

  /// Persist the exact recommendation artwork, caching the reduced preview.
  Future<String?> cacheRecommendationIcon(Track track) async {
    final cacheDir = await getCacheDir();
    final icon = await _cacheIcon(
      track,
      cacheDir,
      suffix: 'recommendation_icon',
    );
    if (icon == null) return null;
    final d = await _db.db;
    final rows = await d.query('cached_tracks',
        columns: ['track_id'],
        where: 'track_id = ?',
        whereArgs: [track.id],
        limit: 1);
    if (rows.isNotEmpty) return icon;
    track.iconUrl = icon;
    return icon;
  }

  /// Remove recommendation-only preview files that no current source uses.
  Future<void> pruneRecommendationIcons(Set<String> usedTrackIds) async {
    final cacheDir = await getCacheDir();
    final pinnedTrackIds = await _db.getCachedTrackIds();
    final retainedIds = {...usedTrackIds, ...pinnedTrackIds};
    await for (final entity in cacheDir.list()) {
      if (entity is! File) continue;
      final match = RegExp(r'^(\d+)_recommendation_icon\.(webp|jpg|png)$')
          .firstMatch(path.basename(entity.path));
      if (match == null || retainedIds.contains(match.group(1))) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
    final cachedAudioIds = await _db.getCachedTrackIds();
    await for (final entity in cacheDir.list()) {
      if (entity is! File) continue;
      final match = RegExp(r'^(\d+)_art\.(webp|jpg|png)$')
          .firstMatch(path.basename(entity.path));
      if (match == null || cachedAudioIds.contains(match.group(1))) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  /// Cache a track
  Future<String?> cacheTrack(
    Track track, {
    void Function(int received, int total)? onProgress,
  }) async {
    final mp3Url = track.mp3Url;
    if (mp3Url == null || mp3Url.isEmpty) return null;

    File? partial;
    IOSink? sink;
    final client = http.Client();
    try {
      final cacheDir = await getCacheDir();
      final filename = '${track.id}.mp3';
      final file = File(path.join(cacheDir.path, filename));
      final download = File('${file.path}.part');
      partial = download;

      // Download file with progress
      final request = http.Request('GET', Uri.parse(mp3Url));
      request.headers['Referer'] =
          'https://www.newgrounds.com/audio/listen/${track.id}';
      request.headers['User-Agent'] = 'Mozilla/5.0';
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final contentLength = response.contentLength ?? 0;
      var receivedBytes = 0;
      sink = download.openWrite();

      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, contentLength);
      }

      await sink.close();
      sink = null;
      if (receivedBytes == 0 ||
          (contentLength > 0 && receivedBytes != contentLength)) {
        return null;
      }

      // Save the cover before publishing so cached tracks work offline.
      final artworkPath = await _cacheArtwork(track, cacheDir);

      // Publish the file only after its complete download and database write.
      final d = await _db.db;
      await d.transaction((txn) async {
        await txn.insert(
          'cached_tracks',
          {
            'track_id': track.id,
            'title': track.title,
            'artist': track.artist,
            'genre': track.genre,
            'icon_url': artworkPath ?? track.iconUrl,
            'duration': track.duration,
            'audio_type': track.audioType,
            'score': track.score,
            'author_url': track.artistAudioUrl,
            'local_path': file.path,
            'cached_at': DateTime.now().millisecondsSinceEpoch,
            'size': receivedBytes,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await download.rename(file.path);
      });

      return file.path;
    } catch (_) {
      return null;
    } finally {
      client.close();
      try {
        await sink?.close();
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
    }
  }

  /// Save both the large cover and the reduced icon next to the audio.
  Future<String?> _cacheArtwork(Track track, Directory cacheDir) async {
    final iconPath = await _cacheIcon(track, cacheDir);
    for (final ext in ['webp', 'jpg', 'png']) {
      final existing = File(path.join(cacheDir.path, '${track.id}_art.$ext'));
      if (await existing.exists()) return existing.path;
    }

    final candidates = <String>{
      track.remoteCoverUrl,
      ...track.artworkUrls,
    };
    for (final remote in candidates) {
      if (remote.isEmpty || !remote.contains('://')) continue;
      final clean = remote.split('?').first;
      final ext = _extensionFor(clean);
      final file = File(path.join(cacheDir.path, '${track.id}_art.$ext'));
      final saved = await _downloadArtwork(clean, file);
      if (saved) return file.path;
    }
    return iconPath;
  }

  /// Save the listing preview (the round disc) for compact widgets such as
  /// the mini player. Never use the full square cover here.
  Future<String?> _cacheIcon(
    Track track,
    Directory cacheDir, {
    String suffix = 'icon',
  }) async {
    if (track.hasLocalIcon) return track.localIconPath;
    for (final ext in ['webp', 'jpg', 'png']) {
      final existing = File(path.join(cacheDir.path, '${track.id}_icon.$ext'));
      if (await existing.exists()) return existing.path;
    }
    final candidates = <String>{
      track.previewIconUrl,
      track.iconUrl,
      track.aIconUrl,
      track.remoteCoverUrl,
    };
    for (final remote in candidates) {
      if (remote.isEmpty || !remote.contains('://')) continue;
      final clean = remote.split('?').first;
      final ext = _extensionFor(clean);
      final file = File(path.join(cacheDir.path, '${track.id}_$suffix.$ext'));
      if (await _downloadArtwork(clean, file)) return file.path;
    }
    return null;
  }

  static String _extensionFor(String url) {
    if (url.endsWith('.png')) return 'png';
    if (url.endsWith('.jpg') || url.endsWith('.jpeg')) return 'jpg';
    return 'webp';
  }

  Future<bool> _downloadArtwork(String url, File file) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'image/*',
          'Referer': 'https://www.newgrounds.com/',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool>? _backfillFuture;

  /// Download covers and reduced icons for entries cached before artwork
  /// was stored locally.
  Future<bool> backfillArtwork() =>
      _backfillFuture ??= _backfillArtwork().whenComplete(() {
        _backfillFuture = null;
      });

  static const _iconVersionFile = '.artwork_icons_v2';

  /// Earlier builds could save the square full cover as the compact icon.
  /// Drop those once so they can be replaced with the round listing preview.
  Future<void> _resetLegacyIcons(Directory cacheDir) async {
    final marker = File(path.join(cacheDir.path, _iconVersionFile));
    if (await marker.exists()) return;
    await for (final entity in cacheDir.list()) {
      if (entity is File &&
          RegExp(r'_icon\.(webp|jpg|png)$').hasMatch(entity.path)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    try {
      await marker.writeAsString('2', flush: true);
    } catch (_) {}
  }

  Future<bool> _backfillArtwork() async {
    final d = await _db.db;
    final rows = await d.query('cached_tracks');
    final cacheDir = await getCacheDir();
    await _resetLegacyIcons(cacheDir);
    var changed = false;
    for (final row in rows) {
      final trackId = row['track_id'] as String;
      final icon = row['icon_url'] as String? ?? '';
      if (_isLocalPath(icon) && await File(_plainPath(icon)).exists()) {
        var hasIcon = false;
        for (final ext in ['webp', 'jpg', 'png']) {
          if (await File(path.join(cacheDir.path, '${trackId}_icon.$ext'))
              .exists()) {
            hasIcon = true;
            break;
          }
        }
        if (hasIcon) continue;
        final track = Track(
          id: trackId,
          title: row['title'] as String? ?? '',
          artist: row['artist'] as String? ?? '',
          genre: row['genre'] as String? ?? '',
          iconUrl: '',
          duration: row['duration'] as int? ?? 0,
          audioType: row['audio_type'] as int? ?? 3,
        );
        if (await _cacheIcon(track, cacheDir) == null) break;
        changed = true;
        continue;
      }
      final track = Track(
        id: trackId,
        title: row['title'] as String? ?? '',
        artist: row['artist'] as String? ?? '',
        genre: row['genre'] as String? ?? '',
        iconUrl: icon,
        duration: row['duration'] as int? ?? 0,
        audioType: row['audio_type'] as int? ?? 3,
      );
      final savedPath = await _cacheArtwork(track, cacheDir);
      if (savedPath == null) {
        break; // Most likely offline; do not stall startup.
      }
      await d.update('cached_tracks', {'icon_url': savedPath},
          where: 'track_id = ?', whereArgs: [track.id]);
      changed = true;
    }
    return changed;
  }

  /// Remove cached track
  Future<bool> removeCachedTrack(String trackId) async {
    final localPath = await getCachedPath(trackId);
    if (localPath == null) return false;

    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
      final cacheDir = await getCacheDir();
      for (final suffix in ['art', 'icon']) {
        for (final ext in ['webp', 'jpg', 'png']) {
          final artwork =
              File(path.join(cacheDir.path, '${trackId}_$suffix.$ext'));
          if (await artwork.exists()) await artwork.delete();
        }
      }

      final d = await _db.db;
      await d.delete(
        'cached_tracks',
        where: 'track_id = ?',
        whereArgs: [trackId],
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get all cached tracks with full metadata
  Future<List<Track>> getCachedTracks() async {
    final d = await _db.db;
    final rows = await d.query('cached_tracks', orderBy: 'cached_at DESC');
    final tracks = <Track>[];
    for (final row in rows) {
      final trackId = row['track_id'] as String;
      final storedIcon = row['icon_url'] as String? ?? '';
      final cover = await getCachedArtworkPath(trackId);
      final icon = await getCachedIconPath(trackId);
      tracks.add(Track(
        id: trackId,
        title: row['title'] as String,
        artist: row['artist'] as String,
        genre: row['genre'] as String? ?? '',
        iconUrl: icon ?? storedIcon,
        localCoverPath: cover,
        duration: row['duration'] as int? ?? 0,
        audioType: row['audio_type'] as int? ?? 3,
        score: row['score'] as String?,
        authorUrl: row['author_url'] as String?,
        mp3Url: row['local_path'] as String, // Local path for playback
      ));
    }
    return tracks;
  }

  /// Get cache info (id, size, cached_at)
  Future<List<CachedTrackInfo>> getCachedTracksInfo() async {
    final d = await _db.db;
    final rows = await d.query(
      'cached_tracks',
      columns: ['track_id', 'local_path', 'cached_at', 'size'],
      orderBy: 'cached_at DESC',
    );
    return rows.map((row) => CachedTrackInfo.fromMap(row)).toList();
  }

  /// Get total cache size
  Future<int> getCacheSize() async {
    final d = await _db.db;
    final result = await d.rawQuery(
      'SELECT SUM(size) as total FROM cached_tracks',
    );
    if (result.isEmpty) return 0;
    return (result.first['total'] as int?) ?? 0;
  }

  /// Clear all cache
  Future<void> clearCache() async {
    final cacheDir = await getCacheDir();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      await cacheDir.create(recursive: true);
    }

    final d = await _db.db;
    await d.delete('cached_tracks');
  }

  /// Clear cache up to target size (removes oldest first)
  Future<void> clearCacheToSize(int targetBytes) async {
    final currentSize = await getCacheSize();
    if (currentSize <= targetBytes) return;

    var toRemove = currentSize - targetBytes;
    final cachedInfo = await getCachedTracksInfo();

    // Sort by oldest first
    cachedInfo.sort((a, b) => a.cachedAt.compareTo(b.cachedAt));

    for (final info in cachedInfo) {
      if (toRemove <= 0) break;
      await removeCachedTrack(info.trackId);
      toRemove -= info.size;
    }
  }
}

class CachedTrackInfo {
  final String trackId;
  final String localPath;
  final int cachedAt;
  final int size;

  CachedTrackInfo({
    required this.trackId,
    required this.localPath,
    required this.cachedAt,
    required this.size,
  });

  factory CachedTrackInfo.fromMap(Map<String, dynamic> map) => CachedTrackInfo(
        trackId: map['track_id'] as String,
        localPath: map['local_path'] as String,
        cachedAt: map['cached_at'] as int,
        size: map['size'] as int,
      );
}
