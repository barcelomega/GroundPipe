import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/model/author.dart';
import '../data/model/track.dart';
import '../data/model/playlist.dart';
import '../data/repository/local_db.dart';
import '../data/repository/ng_repository.dart';
import '../data/repository/cache_manager.dart';
import 'library_viewmodel.dart';

class RecommendationsViewModel extends ChangeNotifier {
  final LocalDb _db = LocalDb.instance;
  final NgRepository _repo = NgRepository();
  final LibraryViewModel library;
  List<Track> _candidateTracks = [];
  int? selectedPlaylistId;
  List<Playlist> availablePlaylists = [];

  RecommendationsViewModel(this.library) {
    library.addListener(_onLibraryChanged);
    _onLibraryChanged();
    unawaited(_loadCached());
  }

  List<Track> tracks = [];
  bool isGathering = false;
  int completedAuthors = 0;
  int totalAuthors = 0;
  String? currentAuthor;
  int currentPage = 0;
  String? error;
  int _generation = 0;
  bool isLoadingCache = false;
  bool _isRebuilding = false;
  bool _isFillingWindow = false;
  bool _fillWindowQueued = false;
  static const int _recommendationLimit = 50;
  static const int _maxFavoritePages = 10;

  String get _currentSource =>
      selectedPlaylistId == null ? 'likes' : 'playlist_$selectedPlaylistId';

  void _onLibraryChanged() {
    availablePlaylists =
        library.playlists.where((p) => p.id != null && p.ngId == null).toList();
    if (selectedPlaylistId != null &&
        !availablePlaylists.any((p) => p.id == selectedPlaylistId)) {
      selectedPlaylistId = null;
    }
    _applyLibraryFilters();
  }

  String _sourceFingerprint(String source, List<Track> tracks) {
    final ids = <String, String>{};
    for (final track in tracks) {
      final author = Author.key(track.authorUrl ?? track.artistAudioUrl);
      ids[track.id] =
          source.startsWith('playlist_') ? '$source:$author' : author;
    }
    final keys = ids.keys.toList()..sort();
    return keys.map((id) => '$id=${ids[id]}').join(',');
  }

  Future<bool> _syncSourceFingerprint(String source, List<Track> tracks) async {
    final fingerprint = _sourceFingerprint(source, tracks);
    final previous = await _db.getRecommendationSourceFingerprint(source);
    if (previous == null) {
      if (source == 'likes') {
        await _db.setRecommendationSourceFingerprint(
            'likes_author_map', _authorMapFingerprint(tracks));
      }
      await _db.setRecommendationSourceFingerprint(source, fingerprint);
      return false;
    }
    if (previous == fingerprint) return false;
    if (source == 'likes') {
      final oldById = <String, String>{};
      final oldMapping =
          await _db.getRecommendationSourceFingerprint('likes_author_map');
      for (final item in (oldMapping ?? '').split(',')) {
        final parts = item.split('=');
        if (parts.length == 2) oldById[parts[0]] = parts[1];
      }
      final currentAuthors = <String, int>{};
      for (final track in tracks) {
        final author = Author.key(track.authorUrl ?? track.artistAudioUrl);
        if (author.isEmpty || author == 'unknown') continue;
        currentAuthors.update(author, (count) => count + 1, ifAbsent: () => 1);
      }
      final departed =
          oldById.values.toSet().difference(currentAuthors.keys.toSet());
      final weights = <String, double>{};
      for (final entry in currentAuthors.entries) {
        final (nextUrl, complete) =
            await _db.getRecommendationAuthorState(entry.key);
        if (!complete || nextUrl != null) continue;
        int? count;
        try {
          count = await _favoriteCountFor(entry.key);
        } catch (e) {
          debugPrint('[recommendations] ${entry.key}: $e');
          count = null;
        }
        if (count == null) continue;
        weights[entry.key] = count == 0 ? 0 : entry.value / math.sqrt(count);
      }
      await _db.removeRecommendationAuthorsAndRebuild(departed, weights,
          source: source);
      await _db.resetIncompleteRecommendationAuthors();
      await _db.setRecommendationSourceFingerprint(
          'likes_author_map', _authorMapFingerprint(tracks));
      await _db.setRecommendationSourceFingerprint(source, fingerprint);
    } else {
      // Keep existing recommendation data intact until the user explicitly
      // refreshes. Source changes only update the fingerprint for comparison.
      await _db.setRecommendationSourceFingerprint(source, fingerprint);
    }
    return true;
  }

  String _authorMapFingerprint(List<Track> tracks) {
    final ids = <String, String>{};
    for (final track in tracks) {
      ids[track.id] = Author.key(track.authorUrl ?? track.artistAudioUrl);
    }
    final keys = ids.keys.toList()..sort();
    return keys.map((id) => '$id=${ids[id]}').join(',');
  }

  Future<void> selectPlaylist(int? playlistId) async {
    if (selectedPlaylistId == playlistId) return;
    selectedPlaylistId = playlistId;
    await _loadCached();
  }

  Future<void> _loadCached() async {
    isLoadingCache = true;
    error = null;
    notifyListeners();
    try {
      await _db.db;
      await _rebuild(fetchCards: false);
    } catch (e) {
      error = 'Could not load recommendations: $e';
    } finally {
      isLoadingCache = false;
      notifyListeners();
      unawaited(_scheduleWindowFill());
    }
  }

  Future<void> refresh() async {
    if (isGathering || library.isLoading) return;
    final generation = ++_generation;
    final sourceTracks = selectedPlaylistId == null
        ? library.stagedLikes.map((like) => like.toTrack()).toList()
        : (await _db.getPlaylistTracks(selectedPlaylistId!))
            .map((track) => track.toTrack())
            .toList();
    final likedByAuthor = <String, int>{};
    for (final track in sourceTracks) {
      final author = Author.key(track.authorUrl ?? track.artistAudioUrl);
      if (author.isEmpty || author == 'unknown') continue;
      final cacheKey = selectedPlaylistId == null
          ? author
          : 'playlist_$selectedPlaylistId:$author';
      likedByAuthor.update(cacheKey, (count) => count + 1, ifAbsent: () => 1);
    }

    final weights = <String, double>{};
    for (final entry in likedByAuthor.entries) {
      weights[entry.key] = 0;
    }
    final sourceKey =
        selectedPlaylistId == null ? 'likes' : 'playlist_$selectedPlaylistId';
    if (selectedPlaylistId != null) {
      final fingerprint = _sourceFingerprint(sourceKey, sourceTracks);
      final previous = await _db.getRecommendationSourceFingerprint(sourceKey);
      if (previous != null && previous != fingerprint) {
        await _db.resetIncompleteRecommendationSourceAuthors(sourceKey);
        await _db.resetRecommendationSource(sourceKey);
        await _db.clearRecommendationCards(sourceKey);
      }
      await _db.setRecommendationSourceFingerprint(sourceKey, fingerprint);
    } else {
      await _syncSourceFingerprint(sourceKey, sourceTracks);
    }
    if (weights.isEmpty) {
      await _db.rebuildRecommendationScores({}, source: sourceKey);
      _candidateTracks = [];
      tracks = [];
      isGathering = false;
      completedAuthors = 0;
      totalAuthors = 0;
      notifyListeners();
      // Drop cached authors/cards that no longer belong to any source.
      await _rebuild(fetchCards: false);
      return;
    }

    isGathering = true;
    completedAuthors = 0;
    totalAuthors = weights.length;
    error = null;
    notifyListeners();

    try {
      var rateLimited = false;
      final failedAuthors = <String>{};
      for (final entry in weights.entries) {
        if (generation != _generation) return;
        final authorName = _authorDisplayName(entry.key, sourceTracks);
        final matchingPlaylists = selectedPlaylistId == null
            ? const <Playlist>[]
            : availablePlaylists
                .where((item) => item.id == selectedPlaylistId)
                .toList();
        final playlist =
            matchingPlaylists.isEmpty ? null : matchingPlaylists.first;
        currentAuthor =
            playlist == null ? authorName : '${playlist.name} - $authorName';
        currentPage = 0;
        notifyListeners();
        try {
          final key = entry.key;
          final (nextUrl, complete) =
              await _db.getRecommendationAuthorState(key);
          if (!complete) {
            await _gatherAuthorFavorites(entry.key, generation,
                nextUrl: nextUrl);
          } else {
            await _checkAuthorForNewFavorites(entry.key, generation);
          }
          if (generation != _generation) return;
          final (_, finished) = await _db.getRecommendationAuthorState(key);
          if (!finished) {
            // Partial lists are resumable, but must not skew the denominator.
            weights[entry.key] = 0;
          } else {
            final favoriteCount = await _favoriteCountFor(entry.key);
            weights[entry.key] = favoriteCount == null || favoriteCount == 0
                ? 0
                : likedByAuthor[entry.key]! / math.sqrt(favoriteCount);
          }
        } catch (e) {
          if (e is NgRateLimitException) {
            error =
                'Newgrounds is rate-limiting requests. Progress is saved; try again later.';
            rateLimited = true;
            break;
          }
          error ??= 'Some favorite lists could not be loaded.';
          failedAuthors.add(entry.key);
          debugPrint('[recommendations] ${entry.key}: $e');
        }
        completedAuthors++;
        notifyListeners();
        if (completedAuthors < totalAuthors) {
          // Keep one second between authors to stay gentle on Newgrounds.
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (generation != _generation) return;
      if (rateLimited || failedAuthors.isNotEmpty) {
        final savedWeights = <String, double>{};
        for (final entry in likedByAuthor.entries) {
          final (_, complete) =
              await _db.getRecommendationAuthorState(entry.key);
          if (!complete) continue;
          int? favoriteCount;
          try {
            favoriteCount = await _favoriteCountFor(entry.key);
          } catch (_) {
            favoriteCount = null;
          }
          savedWeights[entry.key] = favoriteCount == null || favoriteCount == 0
              ? 0
              : entry.value / math.sqrt(favoriteCount);
        }
        await _db.rebuildRecommendationScores(savedWeights, source: sourceKey);
      } else {
        await _db.rebuildRecommendationScores(weights, source: sourceKey);
      }
      await _rebuild();
    } finally {
      if (generation == _generation) {
        isGathering = false;
        currentAuthor = null;
        currentPage = 0;
        notifyListeners();
        unawaited(_scheduleWindowFill());
      }
    }
  }

  Future<int?> _favoriteCountFor(String cacheKey) async {
    final stored = await _db.getRecommendationAuthorFavoriteCount(cacheKey);
    if (stored != null) return stored;
    final info = await _repo.getAuthorFavoritesCount(cacheKey.split(':').last);
    if (info.count == null) return null;
    await _db.setRecommendationAuthorFavoriteCount(cacheKey, info.count!);
    return info.count;
  }

  Future<List<String>> _gatherAuthorFavorites(String username, int generation,
      {required String? nextUrl}) async {
    final key = username;
    final ids = await _db.getRecommendationFavoriteIds(key);
    final seen = {...ids};
    var page = nextUrl == null
        ? 1
        : int.tryParse(Uri.tryParse(nextUrl)?.queryParameters['page'] ?? '') ??
            2;

    // Check the FAVES counter before parsing anything. A rounded count such as
    // "3K" is skipped entirely because it is neither exact nor below the cap.
    final favorites =
        await _repo.getAuthorFavoritesCount(username.split(':').last);
    if (favorites.count == null) return ids;
    final favoriteCount = favorites.count!;
    if (favoriteCount == 0) {
      // An author with no favorites cannot contribute recommendations.
      await _db.removeRecommendationAuthors([key]);
      return const [];
    }
    await _db.setRecommendationAuthorFavoriteCount(key, favoriteCount);

    if (page > _maxFavoritePages) {
      await _db.commitRecommendationFavoritePage(
        key,
        trackIds: const [],
        nextUrl: null,
        favoriteCount: favoriteCount,
      );
      return await _db.getRecommendationFavoriteIds(key);
    }

    var next = nextUrl;
    while (page <= _maxFavoritePages) {
      if (generation != _generation) return ids;
      final (pageTracks, pageNext) = await _repo.getFavoriteAudioIdsPage(
          username.split(':').last,
          page: page,
          url: next);
      currentPage = page;
      notifyListeners();
      final newIds = <String>[];
      for (final track in pageTracks) {
        if (seen.add(track.id)) newIds.add(track.id);
      }
      ids.addAll(newIds);
      final capped = pageNext != null && page == _maxFavoritePages;
      await _db.commitRecommendationFavoritePage(
        key,
        trackIds: newIds,
        nextUrl: capped ? null : pageNext,
        favoriteCount: favoriteCount,
      );
      if (pageNext == null || capped) break;
      next = pageNext;
      page++;
      // One page at a time, with a conservative pause to avoid stressing NG.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (ids.isEmpty) {
      await _db.removeRecommendationAuthors([key]);
      return const [];
    }
    return await _db.getRecommendationFavoriteIds(key);
  }

  /// Checks a fully scanned author for favorites added since the last scan.
  ///
  /// Favorites are newest-first, so scanning stops at the first already known
  /// track. The whole page is still inspected, which also handles a re-fave
  /// that appears above newer tracks. New IDs are inserted ahead of the old
  /// block, then the cache is trimmed to [LocalDb.recommendationFavoriteLimit].
  Future<int> _checkAuthorForNewFavorites(String key, int generation) async {
    final ids = await _db.getRecommendationFavoriteIds(key);
    final known = {...ids};
    final newIds = <String>[];
    var page = 1;
    String? next;
    var sawAnyPage = false;
    var sawAnyId = false;

    while (page <= _maxFavoritePages &&
        newIds.length < LocalDb.recommendationFavoriteLimit) {
      if (generation != _generation) return 0;
      final (pageTracks, pageNext) = await _repo
          .getFavoriteAudioIdsPage(key.split(':').last, page: page, url: next);
      sawAnyPage = true;
      if (pageTracks.isNotEmpty) sawAnyId = true;
      currentPage = page;
      notifyListeners();

      final scan = scanFavoritePage(pageTracks, known);
      newIds.addAll(scan.added);
      if (newIds.length > LocalDb.recommendationFavoriteLimit) {
        newIds.removeRange(LocalDb.recommendationFavoriteLimit, newIds.length);
      }
      if (scan.reachedOld || pageNext == null || pageTracks.isEmpty) break;
      next = pageNext;
      page++;
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    if (newIds.isEmpty) {
      if (ids.isEmpty && sawAnyPage && !sawAnyId) {
        // Complete but empty: drop the tombstone from the cache.
        await _db.removeRecommendationAuthors([key]);
      }
      return 0;
    }

    await _db.prependRecommendationFavoriteIds(key, newIds);
    final storedCount = await _db.getRecommendationAuthorFavoriteCount(key);
    if (storedCount != null) {
      await _db.setRecommendationAuthorFavoriteCount(
          key, storedCount + newIds.length);
    }
    return newIds.length;
  }

  /// Adds every new ID from one favorites page to [known].
  ///
  /// Returns the new IDs in page order and whether an already cached ID was
  /// encountered. The rest of the page is still inspected so a re-fave above
  /// newer tracks does not hide them.
  @visibleForTesting
  static ({List<String> added, bool reachedOld}) scanFavoritePage(
      List<Track> pageTracks, Set<String> known) {
    final added = <String>[];
    var reachedOld = false;
    for (final track in pageTracks) {
      if (known.contains(track.id)) {
        reachedOld = true;
        continue;
      }
      known.add(track.id);
      added.add(track.id);
    }
    return (added: added, reachedOld: reachedOld);
  }

  Future<void> _rebuild({bool fetchCards = true}) async {
    _isRebuilding = true;
    try {
      // The visual-link endpoint accepts at most 25 IDs per request.
      final source =
          selectedPlaylistId == null ? 'likes' : 'playlist_$selectedPlaylistId';
      final rows = await _db.getRecommendationScores(
          limit: _recommendationLimit, source: source);
      final usedSources = await _db.getRecommendationSourcesInUse();
      // Keep filtered tracks in the candidate window. They are hidden from
      // `tracks`, but can return immediately when their Like, playlist entry
      // or blacklist entry is removed.
      final ids = rows.map((row) => row['track_id'] as String).toList();
      final cached = await _db.getRecommendationCards(source);
      final missing = ids.where((id) => !cached.containsKey(id)).toList();
      if (fetchCards && missing.isNotEmpty) {
        final fetched = await _repo.getTrackCardsByIds(missing);
        final encoded = <String, String>{
          for (final track in fetched)
            track.id: jsonEncode(NgRepository.trackToJson(track)),
        };
        await _db.saveRecommendationCards(source, encoded);
        CacheManager.instance.schedulePermanentArtworkSync();
        cached.addAll(encoded);
      }
      final byId = <String, Track>{};
      for (final id in ids) {
        final json = cached[id];
        if (json == null) continue;
        try {
          byId[id] = NgRepository.trackFromJson(
              Map<String, dynamic>.from(jsonDecode(json) as Map));
        } catch (_) {}
      }
      _candidateTracks = ids.map((id) => byId[id]).whereType<Track>().toList();
      _applyLibraryFilters();
      await _db.pruneRecommendationCards(
          source, _candidateTracks.map((t) => t.id).toSet());
      if (fetchCards) unawaited(_cacheRecommendationArtwork(source, tracks));
      final usedAuthorKeys = <String>{};
      final likes = library.stagedLikes.map((like) => like.toTrack()).toList();
      if (usedSources.contains('likes') || source == 'likes') {
        for (final track in likes) {
          final author = Author.key(track.authorUrl ?? track.artistAudioUrl);
          if (author.isNotEmpty && author != 'unknown') {
            usedAuthorKeys.add(author);
          }
        }
      }
      final playlists = await _db.getPlaylists();
      for (final playlist in playlists.where((item) => item.id != null)) {
        final sourceKey = 'playlist_${playlist.id}';
        if (!usedSources.contains(sourceKey) && sourceKey != source) continue;
        final playlistTracks = (await _db.getPlaylistTracks(playlist.id!))
            .map((item) => item.toTrack());
        for (final track in playlistTracks) {
          final author = Author.key(track.authorUrl ?? track.artistAudioUrl);
          if (author.isNotEmpty && author != 'unknown') {
            usedAuthorKeys.add('$sourceKey:$author');
          }
        }
      }
      if (selectedPlaylistId != null) {
        final sourceKey = 'playlist_$selectedPlaylistId';
        final selectedTracks =
            (await _db.getPlaylistTracks(selectedPlaylistId!))
                .map((item) => item.toTrack());
        for (final track in selectedTracks) {
          final author = Author.key(track.authorUrl ?? track.artistAudioUrl);
          if (author.isNotEmpty && author != 'unknown') {
            usedAuthorKeys.add('$sourceKey:$author');
          }
        }
      }
      await _db.pruneRecommendationAuthors(usedAuthorKeys);
      await _db.pruneCardsWithoutRecommendationScores();
      final currentArtworkIds = await _db.getRecommendationCardTrackIds();
      currentArtworkIds.addAll(await _db.getRecentRecommendationArtworkIds());
      await CacheManager.instance.pruneRecommendationIcons(currentArtworkIds);
      CacheManager.instance.schedulePermanentArtworkSync();
    } finally {
      _isRebuilding = false;
    }
  }

  Future<void> _cacheRecommendationArtwork(
      String source, List<Track> visibleTracks) async {
    for (final track in visibleTracks) {
      try {
        final path = await CacheManager.instance.cacheRecommendationIcon(track);
        if (path != null) {
          await _db.saveRecommendationCards(source, {
            track.id: jsonEncode(NgRepository.trackToJson(track)),
          });
        }
      } catch (_) {}
    }
  }

  String _authorDisplayName(String cacheKey, List<Track> sourceTracks) {
    final separator = cacheKey.indexOf(':');
    final username =
        separator < 0 ? cacheKey : cacheKey.substring(separator + 1);
    for (final track in sourceTracks) {
      if (Author.key(track.authorUrl ?? track.artistAudioUrl) == username) {
        return track.artist;
      }
    }
    return username;
  }

  void _applyLibraryFilters() {
    final eligible =
        _candidateTracks.where((track) => !_isFiltered(track.id)).toList();
    if (eligible.length > _recommendationLimit) {
      final kept = eligible.take(_recommendationLimit).toList();
      final trimmed = eligible.skip(_recommendationLimit).toList();
      final trimmedIds = trimmed.map((track) => track.id).toSet();
      _candidateTracks.removeWhere((track) => trimmedIds.contains(track.id));
      tracks = kept;
      final keepIds = _candidateTracks.map((track) => track.id).toSet();
      unawaited(_discardTrimmedTracks(trimmed, _currentSource, keepIds));
    } else {
      tracks = eligible;
    }
    notifyListeners();
    if (tracks.length < _recommendationLimit) {
      unawaited(_scheduleWindowFill());
    }
  }

  bool _isFiltered(String trackId) =>
      library.isStagedLike(trackId) ||
      library.playlistTrackIds.contains(trackId) ||
      library.isBlacklisted(trackId);

  Future<void> _discardTrimmedTracks(
      List<Track> trimmed, String source, Set<String> keepIds) async {
    if (trimmed.isEmpty) return;
    final ids = trimmed.map((track) => track.id).toSet();
    try {
      final currentIds = _candidateTracks.map((track) => track.id).toSet();
      final discarded = ids.difference(currentIds);
      if (discarded.isEmpty) return;
      await _db.pruneRecommendationCards(source, {...keepIds, ...currentIds});
      await CacheManager.instance.removeArtworkForTrackIds(discarded);
      CacheManager.instance.schedulePermanentArtworkSync();
    } catch (_) {}
  }

  Future<void> _scheduleWindowFill() async {
    if (_isRebuilding || isGathering || isLoadingCache) return;
    if (_candidateTracks.isEmpty) return;
    if (tracks.length >= _recommendationLimit) return;
    if (_isFillingWindow) {
      _fillWindowQueued = true;
      return;
    }
    _isFillingWindow = true;
    try {
      await _fillRecommendationWindow();
    } catch (e) {
      debugPrint('[recommendations] fill: $e');
    } finally {
      _isFillingWindow = false;
      if (_fillWindowQueued) {
        _fillWindowQueued = false;
        unawaited(_scheduleWindowFill());
      }
    }
  }

  Future<void> _fillRecommendationWindow() async {
    final source = _currentSource;
    final known = _candidateTracks.map((track) => track.id).toSet();
    var offset = 0;
    const batchSize = 50;
    while (tracks.length < _recommendationLimit) {
      if (_isRebuilding ||
          isGathering ||
          isLoadingCache ||
          source != _currentSource) {
        return;
      }
      final rows = await _db.getRecommendationScores(
          limit: batchSize, offset: offset, source: source);
      if (rows.isEmpty) break;
      offset += rows.length;

      final wanted = <String>[];
      for (final row in rows) {
        if (tracks.length + wanted.length >= _recommendationLimit) break;
        final id = row['track_id'] as String;
        if (known.contains(id) || _isFiltered(id)) continue;
        wanted.add(id);
      }
      if (wanted.isEmpty) {
        if (rows.length < batchSize) break;
        continue;
      }

      final cached = await _db.getRecommendationCards(source);
      final missing = wanted.where((id) => !cached.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        final fetched = await _repo.getTrackCardsByIds(missing);
        final encoded = <String, String>{
          for (final track in fetched)
            if (wanted.contains(track.id))
              track.id: jsonEncode(NgRepository.trackToJson(track)),
        };
        if (encoded.isNotEmpty) {
          await _db.saveRecommendationCards(source, encoded);
          cached.addAll(encoded);
        }
      }

      var appended = 0;
      for (final id in wanted) {
        if (tracks.length >= _recommendationLimit) break;
        if (_isRebuilding ||
            isGathering ||
            isLoadingCache ||
            source != _currentSource) {
          return;
        }
        if (known.contains(id) || _isFiltered(id)) continue;
        final json = cached[id];
        if (json == null) continue;
        try {
          final track = NgRepository.trackFromJson(
              Map<String, dynamic>.from(jsonDecode(json) as Map));
          _candidateTracks.add(track);
          tracks.add(track);
          known.add(id);
          appended++;
        } catch (_) {}
      }
      if (appended > 0) notifyListeners();
      if (appended == 0) break;
      if (rows.length < batchSize) break;
    }
  }

  @override
  void dispose() {
    _generation++;
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
