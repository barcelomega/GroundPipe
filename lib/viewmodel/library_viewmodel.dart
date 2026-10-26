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
  Set<String> playlistTrackIds = {};
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
    playlistTrackIds = await _db.getAllPlaylistTrackIds();

    _stagedLikeIds
      ..clear()
      ..addAll(stagedLikes.map((s) => s.trackId));

    // Load blacklist IDs
    _blacklistedIds.clear();
    final blacklisted = await _db.db;
    final rows = await blacklisted.query('blacklisted_tracks');
    _blacklistedIds.addAll(rows.map((r) => r['track_id'] as String));

    _cache.schedulePermanentArtworkSync();
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
    final trackIds =
        (await _db.getStagedLikes()).map((like) => like.trackId).toList();
    await _db.clearStagedLikes();
    _stagedLikeIds.clear();
    await refresh();
    if (trackIds.isNotEmpty) {
      try {
        await _cache.removeArtworkForTrackIds(trackIds);
      } catch (_) {
        // The scheduled permanent-artwork sync will prune these files too.
      }
    }
  }

  /// Fetch another user's public audio favorites and merge them into Likes.
  ///
  /// Existing likes, blacklisted tracks and duplicate page entries are
  /// skipped, so the import can be run repeatedly without creating duplicates.
  Future<LikesImportResult> importLikes(String username) async {
    final name = username.trim();
    if (name.isEmpty) {
      throw ArgumentError('Enter a Newgrounds username');
    }

    final favorites = await _repo.getAuthorFavoritesCount(name);
    if (favorites.count == null) {
      return LikesImportResult(
        found: 0,
        added: 0,
        skipped: 0,
        tooManyFavorites: favorites.isTooMany,
        countUnavailable: favorites.isUnknown,
      );
    }

    final ids = <String>[];
    final seen = <String>{};
    final visitedPages = <String>{};
    String? nextUrl;
    var page = 1;
    while (page <= 10) {
      final (pageTracks, pageNext) = await _repo.getFavoriteAudioIdsPage(
        name,
        page: page,
        url: nextUrl,
      );
      for (final track in pageTracks) {
        if (seen.add(track.id)) ids.add(track.id);
      }
      if (pageNext == null || !visitedPages.add(pageNext)) break;
      nextUrl = pageNext;
      page++;
      // One page at a time, with a small pause to avoid stressing Newgrounds.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    final existing = await _db.getStagedLikes();
    final blacklisted = await _db.getBlacklistedTracks();
    final alreadyKnown = {
      ...existing.map((like) => like.trackId),
      ...blacklisted.map((row) => row['track_id'] as String),
    };
    final fresh = ids.where((id) => !alreadyKnown.contains(id)).toList();
    if (fresh.isEmpty) {
      return LikesImportResult(
        found: ids.length,
        added: 0,
        skipped: ids.length,
      );
    }

    final freshIds = fresh.toSet();
    final tracksById = <String, Track>{};
    var failedBatches = 0;
    for (var start = 0; start < fresh.length; start += 25) {
      var end = start + 25;
      if (end > fresh.length) end = fresh.length;
      try {
        final cards = await _repo.getTrackCardsByIds(fresh.sublist(start, end));
        for (final track in cards) {
          if (freshIds.contains(track.id)) tracksById[track.id] = track;
        }
      } catch (_) {
        failedBatches++;
      }
    }
    if (tracksById.isEmpty && failedBatches > 0) {
      throw Exception('Could not load the liked tracks');
    }

    final tracks = tracksById.values.toList();
    if (tracks.isNotEmpty) {
      await _db.addStagedLikes(tracks);
    }
    await refresh();

    return LikesImportResult(
      found: ids.length,
      added: tracks.length,
      skipped: ids.length - tracks.length,
    );
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

/// Summary of a Likes import, used by the UI to report the result.
class LikesImportResult {
  final int found;
  final int added;
  final int skipped;
  final bool tooManyFavorites;
  final bool countUnavailable;

  const LikesImportResult({
    required this.found,
    required this.added,
    required this.skipped,
    this.tooManyFavorites = false,
    this.countUnavailable = false,
  });
}
