import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/author.dart';
import '../../data/model/track.dart';
import '../../data/repository/ng_repository.dart';
import '../../data/repository/local_db.dart';
import '../../data/repository/cache_manager.dart';
import '../../data/repository/timeline_feed.dart';
import '../../viewmodel/authors_viewmodel.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../widgets/ng_drawer.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/track_list_item.dart';
import 'authors_screen.dart';

class TimelineProgress extends ChangeNotifier {
  bool isLoading = false;
  int completedAuthors = 0;
  int totalAuthors = 0;
  String? currentAuthor;
  bool isAssembling = false;

  void update({
    required bool isLoading,
    required int completedAuthors,
    required int totalAuthors,
    String? currentAuthor,
    bool isAssembling = false,
  }) {
    this.isLoading = isLoading;
    this.completedAuthors = completedAuthors;
    this.totalAuthors = totalAuthors;
    this.currentAuthor = currentAuthor;
    this.isAssembling = isAssembling;
    notifyListeners();
  }
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const _timelineBatchSize = 25;

  final _repo = NgRepository();
  late final AuthorsViewModel _authors;
  TimelineFeed? _feed;
  List<Track> _tracks = [];
  int _revision = -1;
  int _generation = 0;
  final _db = LocalDb.instance;
  bool _loading = false;
  bool _refreshing = false;
  int _completedAuthors = 0;
  int _totalAuthors = 0;
  String? _currentAuthor;
  bool _assembling = false;
  String? _error;
  String? _cachedAuthorsFingerprint;

  @override
  void initState() {
    super.initState();
    _authors = context.read<AuthorsViewModel>();
    _authors.addListener(_onAuthorsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onAuthorsChanged();
    });
  }

  void _onAuthorsChanged() {
    if (!_authors.loaded || _revision == _authors.revision) return;
    final previousAuthors = _cachedAuthorsFingerprint;
    final fingerprint = _authorsFingerprint;
    final changed = _cachedAuthorsFingerprint != null &&
        _cachedAuthorsFingerprint != fingerprint;
    _cachedAuthorsFingerprint = fingerprint;
    _revision = _authors.revision;
    if (changed) {
      _feed = null;
      if (mounted) setState(() {});
      unawaited(_removeUnsubscribedAuthors(previousAuthors, fingerprint));
    }
    _restoreTimeline();
  }

  Future<void> _removeUnsubscribedAuthors(
      String? previousFingerprint, String currentFingerprint) async {
    if (previousFingerprint == null) return;
    final previous =
        previousFingerprint.split(',').where((id) => id.isNotEmpty).toSet();
    final current =
        currentFingerprint.split(',').where((id) => id.isNotEmpty).toSet();
    final removed = previous.difference(current).map(Author.key).toSet();
    if (removed.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _tracks.removeWhere((track) => removed
          .contains(Author.key(track.authorUrl ?? track.artistAudioUrl)));
    });
  }

  String get _authorsFingerprint => _authors.subscriptions
      .where((author) => !author.blocked)
      .map((author) => author.username)
      .toList()
      .join(',');

  Future<void> _restoreTimeline() async {
    if (!_authors.loaded || _feed != null) return;
    final cached = await _db.getTimelineCache();
    if (!mounted || cached == null) return;
    try {
      final json = jsonDecode(cached.$2) as Map<String, dynamic>;
      final subscriptionsChanged = cached.$1 != _authorsFingerprint;
      final generation = ++_generation;
      final authors = _authors.subscriptions.where((a) => !a.blocked).toList();
      final feed = TimelineFeed.fromJson(
        authors: authors,
        loadPage: _repo.getArtistTracksPage,
        json: json,
      );
      setState(() {
        _feed = feed;
        _tracks = feed.emittedTracks;
        _totalAuthors = feed.totalAuthors;
        _completedAuthors = feed.completedAuthors;
        _refreshing = false;
        _loading = false;
        _error = null;
      });
      context.read<TimelineProgress>().update(
            isLoading: false,
            completedAuthors: feed.completedAuthors,
            totalAuthors: feed.totalAuthors,
          );
      await _db.saveTimelineCache(
          _authorsFingerprint, jsonEncode(feed.toJson()));
      CacheManager.instance.schedulePermanentArtworkSync();
      if (generation != _generation) return;
      if (subscriptionsChanged && feed.hasMore) {
        await _loadMore();
      }
    } catch (_) {
      await _db.clearTimelineCache();
      CacheManager.instance.schedulePermanentArtworkSync();
    }
  }

  bool _onTimelineScroll(ScrollNotification notification) {
    if (!_refreshing &&
        notification is ScrollUpdateNotification &&
        notification.metrics.extentAfter < 400) {
      _loadMore();
    }
    return false;
  }

  Future<void> _refresh() async {
    if (!_authors.loaded) return;
    final generation = ++_generation;
    final authors = _authors.subscriptions.where((a) => !a.blocked).toList();
    await _db.clearTimelineCache();
    if (authors.isEmpty) {
      setState(() {
        _tracks = [];
        _feed = TimelineFeed(
          authors: const [],
          loadPage: _repo.getArtistTracksPage,
        );
        _refreshing = false;
        _loading = false;
        _completedAuthors = 0;
        _totalAuthors = 0;
        _currentAuthor = null;
        _assembling = false;
        _error = null;
      });
      context.read<TimelineProgress>().update(
            isLoading: false,
            completedAuthors: 0,
            totalAuthors: 0,
          );
      return;
    }
    setState(() {
      _refreshing = true;
      _completedAuthors = 0;
      _totalAuthors = authors.length;
      _currentAuthor = null;
      _assembling = false;
      _loading = false;
      _error = null;
      _feed = TimelineFeed(
        authors: authors,
        loadPage: _repo.getArtistTracksPage,
        onProgress: (completed, total) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _completedAuthors = completed;
            _totalAuthors = total;
          });
          context.read<TimelineProgress>().update(
                isLoading: _refreshing,
                completedAuthors: completed,
                totalAuthors: total,
                currentAuthor: _currentAuthor,
                isAssembling: _assembling,
              );
        },
        onMerging: () {
          if (!mounted || generation != _generation) return;
          setState(() {
            _assembling = true;
            _currentAuthor = null;
          });
          context.read<TimelineProgress>().update(
                isLoading: _refreshing,
                completedAuthors: _completedAuthors,
                totalAuthors: _totalAuthors,
                isAssembling: true,
              );
        },
      );
    });
    context.read<TimelineProgress>().update(
          isLoading: true,
          completedAuthors: 0,
          totalAuthors: authors.length,
        );
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final feed = _feed;
    if (_loading || feed == null || (!_refreshing && !feed.hasMore)) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
      _currentAuthor = feed.currentAuthor;
    });
    feed.onAuthorChanged = (author) {
      if (!mounted || generation != _generation) return;
      setState(() => _currentAuthor = author);
      context.read<TimelineProgress>().update(
            isLoading: _refreshing,
            completedAuthors: _completedAuthors,
            totalAuthors: _totalAuthors,
            currentAuthor: author,
            isAssembling: _assembling,
          );
    };
    try {
      final tracks = await feed.take(_timelineBatchSize);
      if (!mounted || generation != _generation) return;
      await _db.saveTimelineCache(
          _authorsFingerprint, jsonEncode(feed.toJson()));
      CacheManager.instance.schedulePermanentArtworkSync();
      setState(() {
        if (_refreshing) {
          _tracks = tracks;
        } else {
          _tracks.addAll(tracks);
        }
        _refreshing = false;
        _loading = false;
        _assembling = false;
        _currentAuthor = null;
      });
      context.read<TimelineProgress>().update(
            isLoading: false,
            completedAuthors: _completedAuthors,
            totalAuthors: _totalAuthors,
          );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      await _db.saveTimelineCache(
          _authorsFingerprint, jsonEncode(feed.toJson()));
      CacheManager.instance.schedulePermanentArtworkSync();
      setState(() {
        _error = e is NgRateLimitException
            ? 'Newgrounds is rate-limiting requests. Timeline progress is saved; try again later.'
            : 'Could not load the timeline. Please try again.';
        _refreshing = false;
        _loading = false;
        _assembling = false;
        _tracks = feed.emittedTracks;
        _currentAuthor = null;
      });
      context.read<TimelineProgress>().update(
            isLoading: false,
            completedAuthors: _completedAuthors,
            totalAuthors: _totalAuthors,
          );
    }
  }

  @override
  void dispose() {
    _authors.removeListener(_onAuthorsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authors = context.watch<AuthorsViewModel>();
    final library = context.watch<LibraryViewModel>();
    final visible = _tracks
        .where((t) => !authors.isBlocked(t) && !library.isBlacklisted(t.id))
        .toList();
    final subscriptions =
        authors.subscriptions.where((a) => !a.blocked).toList();
    return Scaffold(
      drawer: const NgDrawer(),
      appBar: null,
      body: !authors.loaded
          ? Center(
              child: authors.error == null
                  ? const SizedBox.shrink()
                  : TextButton(
                      onPressed: authors.load, child: const Text('Retry')))
          : NestedScrollView(
              floatHeaderSlivers: true,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  title: const Text('Timeline'),
                  floating: true,
                  forceElevated: innerBoxIsScrolled,
                  actions: [
                    IconButton(
                      tooltip: 'Subscriptions',
                      icon: const Icon(Icons.people_outline),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AuthorsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              body: subscriptions.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(
                            height: 320,
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Subscribe to authors to see their latest music here.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (_refreshing)
                          Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Loading timeline...'),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: _assembling || _totalAuthors == 0
                                        ? null
                                        : _completedAuthors / _totalAuthors,
                                  ),
                                  if (_assembling)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Sorting tracks...',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  if (_currentAuthor != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        _currentAuthor!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _onTimelineScroll,
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: visible.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == visible.length) {
                                    if (_loading) {
                                      return const SizedBox.shrink();
                                    }
                                    if (_error != null) {
                                      return ListTile(
                                          title: Text(_error!),
                                          trailing: TextButton(
                                              onPressed: _loadMore,
                                              child: const Text('Retry')));
                                    }
                                    if (_feed?.hasMore == true) {
                                      return TextButton(
                                          onPressed: _loadMore,
                                          child: const Text('Load more'));
                                    }
                                    if (_feed == null) {
                                      return const Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Center(
                                          child: Text(
                                              'Pull down to load timeline'),
                                        ),
                                      );
                                    }
                                    return Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Center(
                                            child: Text(visible.isEmpty
                                                ? 'No music found'
                                                : 'You are all caught up')));
                                  }
                                  final track = visible[index];
                                  return Dismissible(
                                    key: ValueKey('timeline_${track.id}'),
                                    direction: DismissDirection.horizontal,
                                    confirmDismiss: (direction) async {
                                      if (direction ==
                                          DismissDirection.startToEnd) {
                                        final wasLiked =
                                            library.isStagedLike(track.id);
                                        final removedBySwipe = wasLiked;
                                        if (wasLiked) {
                                          await library
                                              .removeStagedLike(track.id);
                                        } else {
                                          await library.addStagedLike(track);
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(wasLiked
                                                  ? 'Removed from Likes'
                                                  : 'Added to Likes'),
                                              action: SnackBarAction(
                                                label: 'Undo',
                                                onPressed: () {
                                                  if (removedBySwipe) {
                                                    library
                                                        .addStagedLike(track);
                                                  } else {
                                                    library.removeStagedLike(
                                                        track.id);
                                                  }
                                                },
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        await library.addToBlacklist(track);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Blocked: ${track.title}'),
                                              action: SnackBarAction(
                                                label: 'Undo',
                                                onPressed: () =>
                                                    library.removeFromBlacklist(
                                                        track.id),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                      return false;
                                    },
                                    background: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 24),
                                      child: Icon(
                                        library.isStagedLike(track.id)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    secondaryBackground: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 24),
                                      child: Icon(
                                        Icons.block,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                    ),
                                    child: TrackListItem(
                                      track: track,
                                      isLiked: library.isStagedLike(track.id),
                                      persistentArtwork: index <
                                          LocalDb.timelineArtworkCacheLimit,
                                      onTap: () {
                                        final player =
                                            context.read<NgViewModel>();
                                        player.setQueueContext(visible);
                                        player.playTrack(track);
                                      },
                                      onLongPress: () =>
                                          showTrackContextMenu(context, track),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}
