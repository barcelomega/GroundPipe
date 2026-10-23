import '../model/track.dart';

enum GenreSort { date, score, views }

typedef GenrePageLoader = Future<List<Track>> Function(
  String genreId,
  int offset,
);

class _GenreState {
  final String genreId;
  final buffer = <Track>[];
  int offset = 0;
  bool hasMore = true;

  _GenreState(this.genreId);
}

/// Fetches one stream per genre and merges them with a k-way merge.
///
/// Date sorting compares track IDs (Newgrounds IDs grow monotonically).
/// Score and views sorting compare the corresponding fields; missing values
/// sort last, and if both values are missing the ID is used. Equal values keep
/// the per-genre stream order.
class MultiGenreFeed {
  static const int pageSize = 30;
  static const int _loadBatchSize = 4;

  final GenreSort sort;
  final GenrePageLoader loadPage;
  final Set<String> genres;
  final List<_GenreState> _states;
  final _seen = <String>{};

  MultiGenreFeed({
    required Iterable<String> genres,
    required this.loadPage,
    this.sort = GenreSort.date,
  })  : genres = Set.unmodifiable(genres.toSet()),
        _states = genres.toSet().map(_GenreState.new).toList();

  bool matches(Set<String> ids, GenreSort sort) =>
      this.sort == sort &&
      genres.length == ids.length &&
      genres.containsAll(ids);

  bool get hasMore =>
      _states.any((state) => state.buffer.isNotEmpty || state.hasMore);

  bool get isComplete => !hasMore;

  Future<List<Track>> take(int count) async {
    if (count <= 0) return [];
    final output = <Track>[];
    while (output.length < count) {
      await _fillEmptyBuffers();
      final best = _bestState();
      if (best == null) break;
      final track = best.buffer.removeAt(0);
      if (_seen.add(track.id)) output.add(track);
    }
    return output;
  }

  Future<void> _fillEmptyBuffers() async {
    final pending = _states
        .where((state) => state.buffer.isEmpty && state.hasMore)
        .toList();
    if (pending.isEmpty) return;
    for (var start = 0; start < pending.length; start += _loadBatchSize) {
      final batch = pending.skip(start).take(_loadBatchSize);
      await Future.wait(batch.map(_loadNextPage));
    }
  }

  Future<void> _loadNextPage(_GenreState state) async {
    final page = await loadPage(state.genreId, state.offset);
    state.offset += page.length;
    state.hasMore = page.isNotEmpty;
    // Keep each genre stream ordered even if the server returns a tie in a
    // different order than the comparator expects.
    final ordered = List<Track>.of(page)..sort(_compare);
    state.buffer.addAll(ordered);
  }

  _GenreState? _bestState() {
    _GenreState? best;
    for (final state in _states) {
      if (state.buffer.isEmpty) continue;
      if (best == null || _compare(state.buffer.first, best.buffer.first) < 0) {
        best = state;
      }
    }
    return best;
  }

  int _compare(Track a, Track b) {
    switch (sort) {
      case GenreSort.date:
        return _compareIdDesc(a, b);
      case GenreSort.score:
        final aScore = _score(a);
        final bScore = _score(b);
        if (aScore == null && bScore == null) return _compareIdDesc(a, b);
        return _compareNumberDesc(aScore, bScore);
      case GenreSort.views:
        final aViews = _views(a);
        final bViews = _views(b);
        if (aViews == null && bViews == null) return _compareIdDesc(a, b);
        return _compareNumberDesc(aViews, bViews);
    }
  }

  static int _compareIdDesc(Track a, Track b) {
    final aId = int.tryParse(a.id);
    final bId = int.tryParse(b.id);
    if (aId != null && bId != null) return bId.compareTo(aId);
    if (aId != null) return -1;
    if (bId != null) return 1;
    return b.id.compareTo(a.id);
  }

  static int _compareNumberDesc(num? a, num? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static double? _score(Track track) =>
      double.tryParse((track.score ?? '').replaceAll(',', '').trim());

  static int? _views(Track track) => _parseCount(track.listens);

  static int? _parseCount(String? raw) {
    if (raw == null) return null;
    final match =
        RegExp(r'([\d.,]+)\s*([KMB])?', caseSensitive: false).firstMatch(raw);
    if (match == null) return null;
    var value = double.tryParse(match.group(1)!.replaceAll(',', '').trim());
    if (value == null) return null;
    switch (match.group(2)?.toUpperCase()) {
      case 'K':
        value *= 1000;
        break;
      case 'M':
        value *= 1000000;
        break;
      case 'B':
        value *= 1000000000;
        break;
    }
    return value.round();
  }
}
