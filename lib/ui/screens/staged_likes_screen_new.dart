import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../widgets/track_list_item.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../../viewmodel/authors_viewmodel.dart';

class StagedLikesScreen extends StatefulWidget {
  const StagedLikesScreen({super.key});

  @override
  State<StagedLikesScreen> createState() => _StagedLikesScreenState();
}

class _StagedLikesScreenState extends State<StagedLikesScreen> {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final lvm = context.watch<LibraryViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final authors = context.watch<AuthorsViewModel>();
    final likes =
        lvm.stagedLikes.where((l) => !authors.isBlocked(l.toTrack())).toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Likes'),
        actions: [
          if (likes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.shuffle),
              onPressed: () {
                final trackList = likes.map((l) => l.toTrack()).toList();
                trackList.shuffle();
                vm.setQueueContext(trackList);
                vm.playTrack(trackList.first);
              },
            ),
        ],
      ),
      body: likes.isEmpty
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
                    'No liked tracks yet',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Swipe left on tracks to add them here',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: likes.length,
              itemBuilder: (context, index) {
                final like = likes[index];
                final track = like.toTrack();

                return TrackListItem(
                  track: track,
                  isLiked: true,
                  onTap: () {
                    final trackList = likes.map((l) => l.toTrack()).toList();
                    vm.setQueueContext(trackList);
                    vm.playTrack(track);
                  },
                  onLongPress: () => _showTrackMenu(context, track, like),
                );
              },
            ),
    );
  }

  void _showTrackMenu(BuildContext context, Track track, stagedLike) {
    final lvm = context.read<LibraryViewModel>();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylist(context, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Remove from Likes'),
              onTap: () async {
                Navigator.pop(ctx);
                await lvm.removeStagedLike(track.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Removed from Likes')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddToPlaylist(BuildContext context, Track track) async {
    final lvm = context.read<LibraryViewModel>();
    final playlist = await showAddToPlaylistSheet(
      context,
      tracks: [track],
      lvm: lvm,
    );
    if (playlist == null || !context.mounted) return;
    await lvm.addTrackToPlaylist(playlist, track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${playlist.name}')),
      );
    }
  }
}
