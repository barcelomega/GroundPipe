import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../data/repository/ng_repository.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../widgets/track_list_item.dart';
import '../widgets/mini_player.dart';
import '../../data/model/author.dart';
import '../../viewmodel/authors_viewmodel.dart';
import '../widgets/author_actions.dart';
import '../widgets/author_avatar.dart';
import '../widgets/track_context_menu.dart';
import 'artist_favorites_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String authorUrl;

  const ArtistScreen({super.key, required this.authorUrl});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
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
    _loadArtistTracks();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400 && !_loading) _loadArtistTracks();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadArtistTracks() async {
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
      final (newTracks, next) =
          await _repo.getArtistTracksPage(_artistName, page: _page);
      if (!mounted) return;
      setState(() {
        final ids = _tracks.map((t) => t.id).toSet();
        final fresh = newTracks.where((t) => ids.add(t.id)).toList();
        _tracks.addAll(fresh);
        _page++;
        _hasMore = next != null && fresh.isNotEmpty;
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
    final authors = context.watch<AuthorsViewModel>();
    final author = Author(username: _artistName, name: _artistName);
    final blocked = authors.stateOf(author).blocked;
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
              child: Text(_artistName.isEmpty ? 'Artist' : _artistName,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'View favorites',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ArtistFavoritesScreen(authorUrl: widget.authorUrl),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerRight,
            child: AuthorActions(author: author),
          ),
        ),
      ),
      body: blocked
          ? const Center(
              child: Text('Author blocked. Unblock to see their music.'))
          : _loading
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
                            'Failed to load artist',
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
                              _loadArtistTracks();
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
                                Icons.music_off,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No tracks found',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          itemCount: visible.length +
                              (_hasMore || _error != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == visible.length) {
                              if (_error != null) {
                                return TextButton(
                                    onPressed: _loadArtistTracks,
                                    child: const Text(
                                        'Could not load more. Retry'));
                              }
                              if (!_loadingMore) {
                                return TextButton(
                                    onPressed: _loadArtistTracks,
                                    child: const Text('Load more'));
                              }
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child:
                                    Center(child: CircularProgressIndicator()),
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
      bottomNavigationBar: vm.currentTrack == null
          ? null
          : const SafeArea(
              top: false,
              child: MiniPlayer(artistLinkEnabled: false),
            ),
    );
  }
}
