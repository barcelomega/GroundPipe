import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/model/author.dart';
import '../data/model/track.dart';
import '../data/repository/local_db.dart';
import '../data/repository/ng_repository.dart';
import 'library_viewmodel.dart';

class RecommendationsViewModel extends ChangeNotifier {
  final LocalDb _db = LocalDb.instance;
  final NgRepository _repo = NgRepository();
  final LibraryViewModel library;
  List<Track> _candidateTracks = [];

  RecommendationsViewModel(this.library) {
    library.addListener(_onLibraryChanged);
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

  void _onLibraryChanged() {
    _applyLibraryFilters();
  }

  Future<void> _loadCached() async {
    try {
      await _db.db;
      await _rebuild();
    } catch (e) {
      error = 'Could not load recommendations: $e';
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (isGathering || library.isLoading) return;
    final generation = ++_generation;
    final likes = List.of(library.stagedLikes);
    final likedByAuthor = <String, int>{};
    for (final like in likes) {
      final track = like.toTrack();
      final author = Author.key(like.authorUrl ?? track.artistAudioUrl);
      if (author.isEmpty || author == 'unknown') continue;
      likedByAuthor.update(author, (count) => count + 1, ifAbsent: () => 1);
    }

    final weights = <String, double>{};
    for (final entry in likedByAuthor.entries) {
      weights[entry.key] = 0;
    }
    if (weights.isEmpty) {
      await _db.rebuildRecommendationScores({});
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
      for (final entry in weights.entries) {
        if (generation != _generation) return;
        currentAuthor = entry.key;
        currentPage = 0;
        notifyListeners();
        try {
          var ids = await _db.getRecommendationFavoriteIds(entry.key);
          final (nextUrl, complete) =
              await _db.getRecommendationAuthorState(entry.key);
          final hadCache = ids.isNotEmpty || complete;
          if (!complete) {
            ids = await _gatherAuthorFavorites(entry.key, generation,
                nextUrl: nextUrl, existingIds: ids);
            if (generation != _generation) return;
            ids = await _db.getRecommendationFavoriteIds(entry.key);
          }
          final (_, finished) =
              await _db.getRecommendationAuthorState(entry.key);
          if (!finished) {
            // Partial lists are resumable, but must not skew the denominator.
            weights[entry.key] = 0;
          } else {
            // The like count is the author's influence; favorite count normalizes it.
            final favoriteCount = hadCache || finished ? ids.length : 0;
            weights[entry.key] = favoriteCount == 0
                ? 0
                : likedByAuthor[entry.key]! / math.sqrt(favoriteCount);
          }
        } catch (e) {
          error ??= 'Some favorite lists could not be loaded.';
          debugPrint('[recommendations] ${entry.key}: $e');
        }
        completedAuthors++;
        notifyListeners();
        if (completedAuthors < totalAuthors) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      if (generation != _generation) return;
      await _db.rebuildRecommendationScores(weights);
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
      {required String? nextUrl, required List<String> existingIds}) async {
    final ids = [...existingIds];
    final seen = {...existingIds};
    var page = nextUrl == null
        ? 1
        : int.tryParse(Uri.tryParse(nextUrl)?.queryParameters['page'] ?? '') ??
            2;
    while (true) {
      if (generation != _generation) return ids;
      final (pageIds, next) = await _repo.getFavoriteAudioIdsPage(username,
          page: page, url: nextUrl);
      currentPage = page;
      notifyListeners();
      for (final id in pageIds) {
        if (seen.add(id)) ids.add(id);
      }
      await _db.saveRecommendationFavoritePage(username, pageIds,
          nextUrl: next);
      if (next == null) break;
      nextUrl = next;
      page++;
      // One page at a time, with a conservative pause to avoid stressing NG.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return ids;
  }

  Future<void> _rebuild({bool fetchCards = true}) async {
    final liked = library.stagedLikes.map((item) => item.trackId).toSet();
    // The visual-link endpoint accepts at most 25 IDs per request.
    final rows = await _db.getRecommendationScores(limit: 50);
    final ids = rows
        .map((row) => row['track_id'] as String)
        .where((id) => !liked.contains(id) && !library.isBlacklisted(id))
        .toList();
    if (!fetchCards) {
      _candidateTracks = [];
      tracks = [];
      notifyListeners();
      return;
    }
    final cards = await _repo.getTrackCardsByIds(ids);
    final byId = {for (final track in cards) track.id: track};
    _candidateTracks = ids.map((id) => byId[id]).whereType<Track>().toList();
    _applyLibraryFilters();
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
