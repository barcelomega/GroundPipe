import '../model/author.dart';
import '../model/track.dart';

typedef ArtistPageLoader = Future<(List<Track>, String?)>
    Function(String artist, {int page});
typedef PublicationDateLoader = Future<void> Function(Track track);

class _AuthorFeed {
  final Author author;
  final tracks = <Track>[];
  final trackIds = <String>{};
  int page = 1;
  int index = 0;
  bool hasMore = true;

  _AuthorFeed(this.author);
}

/// Merge newest-first author streams by real publication time, not track ID.
class TimelineFeed {
  final ArtistPageLoader loadPage;
  final PublicationDateLoader loadDate;
  final List<_AuthorFeed> _sources;
  final _seen = <String>{};
  final List<Track> _emitted = [];
  final void Function(int completed, int total)? onProgress;
  final void Function()? onMerging;
  void Function(String artist)? onAuthorChanged;
  final Set<String> _loadedAuthors = {};
  String? currentAuthor;

  TimelineFeed({
    required List<Author> authors,
    required this.loadPage,
    required this.loadDate,
    this.onProgress,
    this.onMerging,
  }) : _sources = authors.map(_AuthorFeed.new).toList();

  int get totalAuthors => _sources.length;
  List<Track> get emittedTracks => List.unmodifiable(_emitted);
  int get loadedPages =>
      _sources.fold(0, (total, source) => total + source.page - 1);
  int get loadedTrackCount =>
      _sources.fold(0, (total, source) => total + source.tracks.length);
  bool get isComplete => _sources.every(
      (source) => !source.hasMore && source.index >= source.tracks.length);
  int get completedAuthors => _loadedAuthors.length;
  bool get hasMore =>
      _sources.any((s) => s.index < s.tracks.length || s.hasMore);

  Future<Track?> _head(_AuthorFeed source) async {
    while (source.index >= source.tracks.length && source.hasMore) {
      _setCurrentAuthor(source);
      final (tracks, next) =
          await loadPage(source.author.username, page: source.page);
      final fresh = tracks.where((t) => source.trackIds.add(t.id)).toList();
      source.tracks.addAll(fresh);
      final nextPage =
          int.tryParse(Uri.tryParse(next ?? '')?.queryParameters['page'] ?? '');
      source.page = nextPage ?? source.page + 1;
      source.hasMore = next != null;
    }
    if (source.index >= source.tracks.length) {
      _markAuthorLoaded(source);
      return null;
    }
    final track = source.tracks[source.index];
    if (track.publishedAt == null) {
      _setCurrentAuthor(source);
      await loadDate(track);
    }
    if (track.publishedAt == null) {
      throw const FormatException('Missing publication date');
    }
    _markAuthorLoaded(source);
    return track;
  }

  void _setCurrentAuthor(_AuthorFeed source) {
    currentAuthor = source.author.name;
    onAuthorChanged?.call(currentAuthor!);
  }

  void _markAuthorLoaded(_AuthorFeed source) {
    if (_loadedAuthors.add(source.author.username)) {
      onProgress?.call(completedAuthors, totalAuthors);
    }
  }

  Future<List<Track>> take(int count) async {
    if (count <= 0) return [];
    final output = <Track>[];
    // Keep failed batches retryable without losing tracks already consumed.
    final positions = _sources.map((s) => s.index).toList();
    final seen = {..._seen};
    final emitted = [..._emitted];
    try {
      final heads = <Track?>[];
      for (var start = 0; start < _sources.length; start += 4) {
        heads
            .addAll(await Future.wait(_sources.skip(start).take(4).map(_head)));
      }
      onMerging?.call();
      while (output.length < count) {
        int? newest;
        for (var i = 0; i < heads.length; i++) {
          final track = heads[i];
          if (track == null) continue;
          if (newest == null ||
              track.publishedAt!.isAfter(heads[newest]!.publishedAt!)) {
            newest = i;
          }
        }
        if (newest == null) break;
        final track = heads[newest]!;
        if (_seen.add(track.id)) {
          output.add(track);
          _emitted.add(track);
        }
        _sources[newest].index++;
        // The next head is only needed if this batch still needs tracks.
        if (output.length == count) break;
        heads[newest] = await _head(_sources[newest]);
      }
      return output;
    } catch (_) {
      for (var i = 0; i < _sources.length; i++) {
        _sources[i].index = positions[i];
      }
      _seen
        ..clear()
        ..addAll(seen);
      _emitted
        ..clear()
        ..addAll(emitted);
      rethrow;
    }
  }

  Map<String, dynamic> toJson() => {
        'currentAuthor': currentAuthor,
        'authors': [
          for (final source in _sources)
            {
              'username': source.author.username,
              'page': source.page,
              'index': source.index,
              'hasMore': source.hasMore,
              'tracks': source.tracks.map(_trackToJson).toList(),
            }
        ],
        'seen': _seen.toList(),
        'emitted': _emitted.map(_trackToJson).toList(),
      };

  factory TimelineFeed.fromJson({
    required List<Author> authors,
    required ArtistPageLoader loadPage,
    required PublicationDateLoader loadDate,
    required Map<String, dynamic> json,
    void Function(int completed, int total)? onProgress,
    void Function()? onMerging,
  }) {
    final feed = TimelineFeed(
      authors: authors,
      loadPage: loadPage,
      loadDate: loadDate,
      onProgress: onProgress,
      onMerging: onMerging,
    );
    final data = (json['authors'] as List).cast<Map>();
    for (final row in data) {
      _AuthorFeed? source;
      for (final candidate in feed._sources) {
        if (candidate.author.username == row['username']) {
          source = candidate;
          break;
        }
      }
      if (source == null) continue;
      final tracks = (row['tracks'] as List)
          .cast<Map>()
          .map((track) => trackFromJson(Map<String, dynamic>.from(track)))
          .toList();
      source
        ..tracks.addAll(tracks)
        ..trackIds.addAll(tracks.map((track) => track.id))
        ..page = row['page'] as int
        ..index = row['index'] as int
        ..hasMore = row['hasMore'] as bool;
    }
    feed.currentAuthor = json['currentAuthor'] as String?;
    final activeTrackIds = feed._sources
        .expand((source) => source.tracks)
        .map((track) => track.id)
        .toSet();
    feed._seen.addAll(
        (json['seen'] as List).cast<String>().where(activeTrackIds.contains));
    feed._emitted.addAll((json['emitted'] as List)
        .cast<Map>()
        .map((track) => trackFromJson(Map<String, dynamic>.from(track)))
        .where((track) => activeTrackIds.contains(track.id)));
    for (final source in feed._sources) {
      if (!source.hasMore && source.index >= source.tracks.length) {
        feed._loadedAuthors.add(source.author.username);
      }
    }
    return feed;
  }

  static Map<String, dynamic> _trackToJson(Track track) => {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'authorUrl': track.authorUrl,
        'iconUrl': track.iconUrl,
        'duration': track.duration,
        'audioType': track.audioType,
        'genre': track.genre,
        'publishedAt': track.publishedAt?.toIso8601String(),
      };

  static Track trackFromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        authorUrl: json['authorUrl'] as String?,
        iconUrl: json['iconUrl'] as String,
        duration: json['duration'] as int,
        audioType: json['audioType'] as int,
        genre: json['genre'] as String? ?? '',
      )..publishedAt = DateTime.tryParse(json['publishedAt'] as String? ?? '');
}
