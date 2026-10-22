import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/model/author.dart';
import '../data/model/track.dart';
import '../data/model/playlist.dart';
import '../data/repository/local_db.dart';
import '../data/repository/ng_repository.dart';
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
        final count =
            (await _db.getRecommendationFavoriteIds(entry.key)).length;
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
      tracks = [];
      isGathering = false;
      completedAuthors = 0;
      totalAuthors = 0;
      notifyListeners();
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
          var ids = await _db.getRecommendationFavoriteIds(key);
          final (nextUrl, complete) =
              await _db.getRecommendationAuthorState(key);
          if (!complete) {
            ids = await _gatherAuthorFavorites(entry.key, generation,
                nextUrl: nextUrl);
            if (generation != _generation) return;
            ids = await _db.getRecommendationFavoriteIds(key);
          }
          final (_, finished) = await _db.getRecommendationAuthorState(key);
          if (!finished) {
            // Partial lists are resumable, but must not skew the denominator.
            weights[entry.key] = 0;
          } else {
            final favoriteCount = ids.length;
            weights[entry.key] = favoriteCount == 0
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
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      if (generation != _generation) return;
      if (rateLimited || failedAuthors.isNotEmpty) {
        final savedWeights = <String, double>{};
        for (final entry in likedByAuthor.entries) {
          final (_, complete) =
              await _db.getRecommendationAuthorState(entry.key);
          if (!complete) continue;
          final favoriteCount =
              (await _db.getRecommendationFavoriteIds(entry.key)).length;
          savedWeights[entry.key] =
              favoriteCount == 0 ? 0 : entry.value / math.sqrt(favoriteCount);
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
      }
    }
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
    var next = nextUrl;
    while (true) {
      if (generation != _generation) return ids;
      final (pageIds, pageNext) = await _repo.getFavoriteAudioIdsPage(
          username.split(':').last,
          page: page,
          url: next);
      currentPage = page;
      notifyListeners();
      final newIds = pageIds.where(seen.add).toList();
      ids.addAll(newIds);
      await _db.commitRecommendationFavoritePage(key,
          trackIds: newIds, nextUrl: pageNext);
      if (pageNext == null) break;
      next = pageNext;
      page++;
      // One page at a time, with a conservative pause to avoid stressing NG.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return await _db.getRecommendationFavoriteIds(key);
  }

  Future<void> _rebuild({bool fetchCards = true}) async {
    final liked = library.stagedLikes.map((item) => item.trackId).toSet();
    // The visual-link endpoint accepts at most 25 IDs per request.
    final source =
        selectedPlaylistId == null ? 'likes' : 'playlist_$selectedPlaylistId';
    final rows = await _db.getRecommendationScores(limit: 50, source: source);
    final ids = rows
        .map((row) => row['track_id'] as String)
        .where((id) => !liked.contains(id) && !library.isBlacklisted(id))
        .toList();
    final cached = await _db.getRecommendationCards(source);
    final missing = ids.where((id) => !cached.containsKey(id)).toList();
    if (fetchCards && missing.isNotEmpty) {
      final fetched = await _repo.getTrackCardsByIds(missing);
      final encoded = <String, String>{
        for (final track in fetched)
          track.id: jsonEncode(NgRepository.trackToJson(track)),
      };
      await _db.saveRecommendationCards(source, encoded);
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
    final liked = library.stagedLikes.map((item) => item.trackId).toSet();
    tracks = _candidateTracks
        .where((track) =>
            !liked.contains(track.id) && !library.isBlacklisted(track.id))
        .toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
