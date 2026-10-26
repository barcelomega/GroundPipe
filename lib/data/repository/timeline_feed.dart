import '../model/author.dart';
import '../model/track.dart';

typedef ArtistPageLoader = Future<(List<Track>, String?)>
    Function(String artist, {int page});

class _AuthorFeed {
  final Author author;
  bool loaded = false;

  _AuthorFeed(this.author);
}

/// Builds a newest-first timeline from one page per author.
///
/// Newgrounds track IDs grow monotonically, so a larger ID means a later
/// submission. All tracks from the loaded pages go into one pool, which is
/// sorted by ID and capped at [candidateLimit] entries.
class TimelineFeed {
  static const int candidateLimit = 250;
  static const _cacheVersion = 3;
  static const _loadBatchSize = 4;

  final ArtistPageLoader loadPage;
  final List<_AuthorFeed> _sources;
  final _pool = <Track>[];
  final _seen = <String>{};
  final List<Track> _emitted = [];
  final void Function(int completed, int total)? onProgress;
  final void Function()? onMerging;
  void Function(String artist)? onAuthorChanged;
  String? currentAuthor;

  TimelineFeed({
    required List<Author> authors,
    required this.loadPage,
    this.onProgress,
    this.onMerging,
  }) : _sources = authors.map(_AuthorFeed.new).toList();

  int get totalAuthors => _sources.length;
  List<Track> get emittedTracks => List.unmodifiable(_emitted);
  int get loadedPages => _sources.where((source) => source.loaded).length;
  int get loadedTrackCount => _emitted.length + _pool.length;
  bool get isComplete =>
      _pool.isEmpty && _sources.every((source) => source.loaded);
  int get completedAuthors => loadedPages;
  bool get hasMore =>
      _pool.isNotEmpty || _sources.any((source) => !source.loaded);

  Future<void> _ensureLoaded() async {
    final pending = _sources.where((source) => !source.loaded).toList();
    if (pending.isEmpty) return;

    var loadedAny = false;
    for (var start = 0; start < pending.length; start += _loadBatchSize) {
      final batch = pending.skip(start).take(_loadBatchSize);
      await Future.wait(batch.map((source) async {
        _setCurrentAuthor(source);
        final (tracks, _) = await loadPage(source.author.username, page: 1);
        for (final track in tracks) {
          if (track.authorUrl == null || track.authorUrl!.trim().isEmpty) {
            track.authorUrl =
                'https://${source.author.username}.newgrounds.com/audio';
          }
          if (_seen.add(track.id)) _pool.add(track);
        }
        source.loaded = true;
        loadedAny = true;
        onProgress?.call(completedAuthors, totalAuthors);
      }));
    }

    if (loadedAny) {
      _sortAndCap();
      onMerging?.call();
    }
  }

  void _setCurrentAuthor(_AuthorFeed source) {
    currentAuthor = source.author.name;
    onAuthorChanged?.call(currentAuthor!);
  }

  Future<List<Track>> take(int count) async {
    if (count <= 0) return [];
    await _ensureLoaded();
    if (_pool.isEmpty) return [];

    final takeCount = count < _pool.length ? count : _pool.length;
    final output = _pool.sublist(0, takeCount);
    _pool.removeRange(0, takeCount);
    _emitted.addAll(output);
    return output;
  }

  void _sortAndCap() {
    _pool.sort(_compareNewest);
    final remaining = candidateLimit - _emitted.length;
    if (remaining <= 0) {
      _pool.clear();
    } else if (_pool.length > remaining) {
      _pool.removeRange(remaining, _pool.length);
    }
  }

  static int _compareNewest(Track a, Track b) {
    final aId = int.tryParse(a.id);
    final bId = int.tryParse(b.id);
    if (aId != null && bId != null) return bId.compareTo(aId);
    if (aId != null) return -1;
    if (bId != null) return 1;
    return b.id.compareTo(a.id);
  }

  Map<String, dynamic> toJson() => {
        'version': _cacheVersion,
        'currentAuthor': currentAuthor,
        'authors': [
          for (final source in _sources)
            {
              'username': source.author.username,
              'loaded': source.loaded,
            }
        ],
        'seen': _seen.toList(),
        'pool': _pool.map(_trackToJson).toList(),
        'emitted': _emitted.map(_trackToJson).toList(),
      };

  factory TimelineFeed.fromJson({
    required List<Author> authors,
    required ArtistPageLoader loadPage,
    required Map<String, dynamic> json,
    void Function(int completed, int total)? onProgress,
    void Function()? onMerging,
  }) {
    if (json['version'] != _cacheVersion) {
      throw const FormatException('Unsupported timeline cache');
    }
    final feed = TimelineFeed(
      authors: authors,
      loadPage: loadPage,
      onProgress: onProgress,
      onMerging: onMerging,
    );
    final data = (json['authors'] as List? ?? const []).cast<Map>();
    for (final row in data) {
      final username = row['username'] as String?;
      final loaded = row['loaded'] as bool? ?? false;
      for (final source in feed._sources) {
        if (source.author.username == username) {
          source.loaded = loaded;
          break;
        }
      }
    }
    feed.currentAuthor = json['currentAuthor'] as String?;
    final allowedAuthors =
        feed._sources.map((source) => source.author.username).toSet();
    List<Track> parseTracks(String key) => (json[key] as List? ?? const [])
        .cast<Map>()
        .map((track) => trackFromJson(Map<String, dynamic>.from(track)))
        .where((track) => _belongsTo(track, allowedAuthors))
        .toList();

    feed._emitted.addAll(parseTracks('emitted'));
    final emittedIds = feed._emitted.map((track) => track.id).toSet();
    feed._pool.addAll(
        parseTracks('pool').where((track) => !emittedIds.contains(track.id)));
    feed._seen.addAll((json['seen'] as List? ?? const []).cast<String>());
    feed._seen.addAll(feed._emitted.map((track) => track.id));
    feed._seen.addAll(feed._pool.map((track) => track.id));
    feed._sortAndCap();
    return feed;
  }

  static bool _belongsTo(Track track, Set<String> usernames) {
    final raw = track.authorUrl ?? track.artistAudioUrl;
    if (raw.trim().isEmpty) return true;
    return usernames.contains(Author.key(raw));
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
        genreVerified: (json['genre'] as String? ?? '').isNotEmpty,
      );
}
