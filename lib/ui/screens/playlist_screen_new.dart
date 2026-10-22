import 'package:flutter/material.dart';
import '../../viewmodel/authors_viewmodel.dart';
import 'package:provider/provider.dart';

import '../../data/model/playlist.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_list_item.dart';
import '../widgets/track_context_menu.dart';

class PlaylistScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistScreen({super.key, required this.playlist});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  List<PlaylistTrack> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() => _loading = true);
    final lvm = context.read<LibraryViewModel>();
    if (widget.playlist.id != null) {
      final tracks = await lvm.getPlaylistTracks(widget.playlist.id!);
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final authors = context.watch<AuthorsViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              title: Text(widget.playlist.name),
              floating: true,
              actions: [
                if (_tracks.any((t) => !authors.isBlocked(t.toTrack())))
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    onPressed: () {
                      final trackList = _tracks
                          .map((t) => t.toTrack())
                          .where((t) => !authors.isBlocked(t))
                          .toList();
                      trackList.shuffle();
                      vm.setQueueContext(trackList);
                      vm.playTrack(trackList.first);
                    },
                  ),
              ],
            ),

            // Header
            if (widget.playlist.description != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.playlist.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            // Track count
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${_tracks.length} ${_tracks.length == 1 ? 'track' : 'tracks'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // Tracks
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_note_outlined,
                        size: 64,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No tracks yet',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverReorderableList(
                itemCount: _tracks.length,
                onReorder: (oldIndex, newIndex) async {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }

                  // Reorder in local list
                  setState(() {
                    final item = _tracks.removeAt(oldIndex);
                    _tracks.insert(newIndex, item);
                  });

                  // Update order in database
                  final lvm = context.read<LibraryViewModel>();
                  final messenger = ScaffoldMessenger.of(context);
                  final playlistId = widget.playlist.id;
                  if (playlistId != null) {
                    try {
                      await lvm.reorderPlaylistTracks(
                        playlistId,
                        _tracks.map((t) => t.trackId).toList(),
                      );
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not save the new track order'),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (context, index) {
                  final playlistTrack = _tracks[index];
                  final track = playlistTrack.toTrack();
                  if (authors.isBlocked(track)) {
                    return SizedBox.shrink(
                        key: ValueKey(playlistTrack.trackId));
                  }
                  final isCurrent = vm.currentTrack?.id == track.id;
                  return Material(
                    key: ValueKey(playlistTrack.trackId),
                    color: isCurrent
                        ? Color.alphaBlend(
                            colorScheme.onSurface.withOpacity(0.08),
                            colorScheme.surface,
                          )
                        : colorScheme.surface,
                    child: Row(
                      children: [
                        Expanded(
                          child: TrackListItem(
                            track: track,
                            showLikedIndicator: false,
                            showGenre: false,
                            highlightCurrentTrack: false,
                            persistentArtwork: true,
                            onTap: () {
                              final trackList =
                                  _tracks.map((t) => t.toTrack()).toList();
                              vm.setQueueContext(trackList);
                              vm.playTrack(track);
                            },
                            onLongPress: () =>
                                _showTrackMenu(context, track, playlistTrack),
                          ),
                        ),
                        ReorderableDelayedDragStartListener(
                          key: ValueKey('${playlistTrack.trackId}-drag-handle'),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 18),
                            child: Icon(
                              Icons.drag_handle,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: vm.currentTrack == null
          ? null
          : const SafeArea(
              top: false,
              child: MiniPlayer(),
            ),
    );
  }

  void _showTrackMenu(
      BuildContext context, track, PlaylistTrack playlistTrack) {
    final lvm = context.read<LibraryViewModel>();
    showTrackContextMenu(
      context,
      track,
      showRemove: true,
      removeLabel: 'Remove from playlist',
      onRemove: () async {
        final id = widget.playlist.id;
        if (id == null) return;
        await lvm.removeTrackFromPlaylist(id, playlistTrack.trackId);
        await _loadTracks();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from playlist')),
          );
        }
      },
    );
  }
}
