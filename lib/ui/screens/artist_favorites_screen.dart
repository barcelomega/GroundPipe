import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../data/repository/ng_repository.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../widgets/track_list_item.dart';
import '../widgets/mini_player.dart';
import '../../data/model/author.dart';
import '../widgets/author_avatar.dart';
import '../widgets/track_context_menu.dart';

class ArtistFavoritesScreen extends StatefulWidget {
  final String authorUrl;

  const ArtistFavoritesScreen({super.key, required this.authorUrl});

  @override
  State<ArtistFavoritesScreen> createState() => _ArtistFavoritesScreenState();
}

class _ArtistFavoritesScreenState extends State<ArtistFavoritesScreen> {
  bool _loading = true;
  String? _error;
  late final String _artistName;
  final List<Track> _tracks = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  final _repo = NgRepository();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _artistName = Author.key(widget.authorUrl);
    _scroll.addListener(_onScroll);
    _loadFavorites();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400 && !_loading) _loadFavorites();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    if (_loadingMore || !_hasMore) return;

    setState(() {
      if (_page == 1) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      // Get favorite tracks for this page (with full metadata)
      final (tracks, next) = await _repo.getFavoriteAudioIdsPage(_artistName, page: _page);
      
      if (tracks.isEmpty && _page == 1) {
        if (!mounted) return;
        setState(() {
          _hasMore = false;
          _loading = false;
          _loadingMore = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        final trackIds = _tracks.map((t) => t.id).toSet();
        final fresh = tracks.where((t) => trackIds.add(t.id)).toList();
        _tracks.addAll(fresh);
        _page++;
        _hasMore = next != null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final lvm = context.watch<LibraryViewModel>();
    final visible = _tracks.where((t) => !lvm.isBlacklisted(t.id)).toList();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(children: [
          AuthorAvatar(author: _artistName, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_artistName\'s Favorites',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _tracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load favorites',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _page = 1;
                            _tracks.clear();
                            _hasMore = true;
                          });
                          _loadFavorites();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : visible.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.favorite_border,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No favorites found',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        ListView.builder(
                          controller: _scroll,
                          itemCount: visible.length +
                              (_hasMore || _error != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == visible.length) {
                              if (_error != null) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: TextButton(
                                      onPressed: _loadFavorites,
                                      child: const Text('Could not load more. Retry'),
                                    ),
                                  ),
                                );
                              }
                              if (!_loadingMore) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: TextButton(
                                      onPressed: _loadFavorites,
                                      child: const Text('Load more'),
                                    ),
                                  ),
                                );
                              }
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final track = visible[index];
                            return TrackListItem(
                              track: track,
                              isLiked: lvm.isStagedLike(track.id),
                              onTap: () {
                                vm.setQueueContext(visible);
                                vm.playTrack(track);
                              },
                              onLongPress: () =>
                                  showTrackContextMenu(context, track),
                            );
                          },
                        ),
                        if (vm.currentTrack != null)
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: MiniPlayer(),
                          ),
                      ],
                    ),
    );
  }
}
