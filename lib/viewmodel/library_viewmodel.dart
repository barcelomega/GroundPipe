import 'package:flutter/foundation.dart';

import '../data/model/playlist.dart';
import '../data/model/track.dart';
import '../data/repository/local_db.dart';
import '../data/repository/cache_manager.dart';
import '../data/repository/ng_repository.dart';

class LibraryViewModel extends ChangeNotifier {
  final _db = LocalDb.instance;
  final _cache = CacheManager.instance;
  final _repo = NgRepository();
  final _cacheOperations = <String>{};
  int cacheRevision = 0;

  bool isCacheBusy(String trackId) => _cacheOperations.contains(trackId);

  List<Playlist> playlists = [];
  List<StagedLike> stagedLikes = [];
  bool isLoading = false;

  String? lastError;

  final _blacklistedIds = <String>{};
  final _stagedLikeIds = <String>{};

  LibraryViewModel() {
    _init();
  }

  Future<void> _init() async {
    await refresh();
    final changed = await _cache.backfillArtwork();
    if (changed) {
      cacheRevision++;
      notifyListeners();
    }
  }

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();

    playlists = await _db.getPlaylists();
    stagedLikes = await _db.getStagedLikes();

    _stagedLikeIds
      ..clear()
      ..addAll(stagedLikes.map((s) => s.trackId));

    // Load blacklist IDs
    _blacklistedIds.clear();
    final blacklisted = await _db.db;
    final rows = await blacklisted.query('blacklisted_tracks');
    _blacklistedIds.addAll(rows.map((r) => r['track_id'] as String));

    isLoading = false;
    notifyListeners();
  }

  // Blacklist methods
  bool isBlacklisted(String trackId) => _blacklistedIds.contains(trackId);

  Future<void> addToBlacklist(Track track) async {
    await _db.addToBlacklist(track);
    _blacklistedIds.add(track.id);
    notifyListeners();
  }

  Future<void> removeFromBlacklist(String trackId) async {
    await _db.removeFromBlacklist(trackId);
    _blacklistedIds.remove(trackId);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getBlacklistedTracks() async {
    return await _db.getBlacklistedTracks();
  }

  // Staged likes methods
  bool isStagedLike(String trackId) => _stagedLikeIds.contains(trackId);

  Future<void> addStagedLike(Track track) async {
    await _db.addStagedLike(track);
    _stagedLikeIds.add(track.id);
    await refresh();
  }

  Future<void> removeStagedLike(String trackId) async {
    await _db.removeStagedLike(trackId);
    _stagedLikeIds.remove(trackId);
    await refresh();
  }

  Future<void> clearStagedLikes() async {
    await _db.clearStagedLikes();
    _stagedLikeIds.clear();
    await refresh();
  }

  // Playlist management
  Future<Playlist> createPlaylist(String name, {String? description}) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Playlist name cannot be empty');
    }
    // Identical names are allowed; all selection and mutation uses the stable
    // database ID, so duplicate titles cannot route tracks to the wrong list.
    final p =
        await _db.createPlaylist(normalizedName, description: description);
    await refresh();
    return p;
  }

  Future<bool> renamePlaylist(int id, String name) async {
    await _db.renamePlaylist(id, name);
    await refresh();
    return true;
  }

  Future<bool> deletePlaylist(Playlist playlist) async {
    final id = playlist.id;
    if (id == null || playlist.ngId != null) return false;
    await _db.deletePlaylist(id);
    await refresh();
    return true;
  }

  Future<List<PlaylistTrack>> getPlaylistTracks(int playlistId) =>
      _db.getPlaylistTracks(playlistId);

  Future<bool> isTrackInPlaylist(int playlistId, String trackId) =>
      _db.isTrackInPlaylist(playlistId, trackId);

  Future<void> addTrackToPlaylist(Playlist pl, Track track) async {
    if (pl.id != null) {
      await _db.addTrackToPlaylist(pl.id!, track);
    }
    await refresh();
  }

  Future<void> addTracksToPlaylist(Playlist pl, List<Track> tracks) async {
    if (pl.id != null) {
      for (final track in tracks) {
        await _db.addTrackToPlaylist(pl.id!, track);
      }
    }
    await refresh();
  }

  Future<Playlist> createPlaylistWithTrack(String name, Track track) async {
    final pl = await createPlaylist(name);
    if (pl.id != null) {
      await _db.addTrackToPlaylist(pl.id!, track);
      await refresh();
    }
    return pl;
  }

  Future<bool> removeTrackFromPlaylist(int playlistId, String trackId) async {
    await _db.removeTrackFromPlaylist(playlistId, trackId);
    await refresh();
    return true;
  }

  Future<List<PlaylistTrack>> loadPlaylistTracks(Playlist playlist) async {
    if (playlist.id == null) return [];
    return await _db.getPlaylistTracks(playlist.id!);
  }

  Future<void> reorderPlaylistTracks(
      int playlistId, List<String> trackIds) async {
    await _db.reorderPlaylistTracks(playlistId, trackIds);
    notifyListeners();
  }

  // Cache management
  Future<bool> isCached(String trackId) => _cache.isCached(trackId);
  Future<bool> isTrackCached(String trackId) => isCached(trackId);

  Future<String?> getCachedPath(String trackId) =>
      _cache.getCachedPath(trackId);

  Future<String?> cacheTrack(
    Track track, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!_cacheOperations.add(track.id)) return null;
    notifyListeners();
    try {
      if (track.mp3Url == null || track.mp3Url!.isEmpty) {
        await _repo.enrichTrack(track);
      }
      return await _cache.cacheTrack(track, onProgress: onProgress);
    } finally {
      _cacheOperations.remove(track.id);
      cacheRevision++;
      notifyListeners();
    }
  }

  Future<bool> removeCachedTrack(String trackId) async {
    if (!_cacheOperations.add(trackId)) return false;
    notifyListeners();
    try {
      return await _cache.removeCachedTrack(trackId);
    } finally {
      _cacheOperations.remove(trackId);
      cacheRevision++;
      notifyListeners();
    }
  }

  Future<List<Track>> getCachedTracks() => _cache.getCachedTracks();

  Future<String?> getCachedArtworkPath(String trackId) =>
      _cache.getCachedArtworkPath(trackId);

  Future<String?> getCachedIconPath(String trackId) =>
      _cache.getCachedIconPath(trackId);

  Future<bool> backfillCachedArtwork() async {
    final changed = await _cache.backfillArtwork();
    if (changed) {
      cacheRevision++;
      notifyListeners();
    }
    return changed;
  }

  Future<int> getCacheSize() => _cache.getCacheSize();

  Future<void> clearCache() async {
    await _cache.clearCache();
    cacheRevision++;
    notifyListeners();
  }

  Future<void> clearCacheToSize(int targetBytes) =>
      _cache.clearCacheToSize(targetBytes);
}
