import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../widgets/track_list_item.dart';
import '../widgets/track_context_menu.dart';
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
                  onLongPress: () => showTrackContextMenu(context, track),
                );
              },
            ),
    );
  }
}
