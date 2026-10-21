import 'package:flutter/material.dart';

import '../../data/model/track.dart';
import 'package:provider/provider.dart';
import '../../viewmodel/authors_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import 'track_artwork.dart';
import 'track_genre.dart';

class TrackListItem extends StatelessWidget {
  final Track track;
  final bool isLiked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TrackListItem({
    super.key,
    required this.track,
    this.isLiked = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final authors = context.watch<AuthorsViewModel?>();
    if (authors?.isBlocked(track) == true) return const SizedBox.shrink();
    final isCurrent = context.select<NgViewModel, bool>(
      (vm) => vm.currentTrack?.id == track.id,
    );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isCurrent
          ? Color.alphaBlend(
              colorScheme.onSurface.withOpacity(0.08),
              colorScheme.surface,
            )
          : Colors.transparent,
      child: ListTile(
        leading: TrackArtwork(track: track, size: 48, compact: true),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: TrackGenre(track: track)),
              if (isLiked) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.favorite,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
