import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../theme/ng_theme.dart';
import 'add_to_playlist_sheet.dart';

/// Shows a context menu for a track.
Future<void> showTrackContextMenu(
  BuildContext context,
  Track track, {
  bool showAddToPlaylist = true,
  bool showLike = true,
  bool showDislike = true,
  bool showRemove = false,
  VoidCallback? onRemove,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TrackContextMenu(
      track: track,
      showAddToPlaylist: showAddToPlaylist,
      showLike: showLike,
      showDislike: showDislike,
      showRemove: showRemove,
      onRemove: onRemove,
    ),
  );
}

class _TrackContextMenu extends StatelessWidget {
  final Track track;
  final bool showAddToPlaylist;
  final bool showLike;
  final bool showDislike;
  final bool showRemove;
  final VoidCallback? onRemove;

  const _TrackContextMenu({
    required this.track,
    required this.showAddToPlaylist,
    required this.showLike,
    required this.showDislike,
    required this.showRemove,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lvm = context.watch<LibraryViewModel>();

    return Container(
      decoration: BoxDecoration(
        color: ngBlack,
        border: Border.all(color: ngHairline),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with track info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ngHairline)),
              ),
              child: Row(
                children: [
                  // Track icon
                  if (track.iconUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        track.iconUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          color: ngWhite.withOpacity(0.05),
                          child: Icon(Icons.music_note, color: ngWhite.withOpacity(0.3), size: 24),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: ngWhite.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.music_note, color: ngWhite.withOpacity(0.3), size: 24),
                    ),
                  const SizedBox(width: 12),
                  // Track title and artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          style: TextStyle(
                            fontFamily: ngHeaderFont,
                            fontSize: 14,
                            color: ngWhite,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          style: TextStyle(
                            color: ngWhite.withOpacity(0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: ngWhite.withOpacity(0.6), size: 24),
                  ),
                ],
              ),
            ),

            // Actions
            if (showAddToPlaylist)
              _MenuItem(
                icon: Icons.playlist_add,
                label: 'Add to Playlist',
                onTap: () async {
                  Navigator.pop(context);
                  final playlist = await showAddToPlaylistSheet(
                    context,
                    tracks: [track],
                    lvm: lvm,
                  );
                  if (playlist != null && context.mounted) {
                    await lvm.addTrackToPlaylist(playlist, track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'Added to "${playlist.name}"',
                          style: TextStyle(color: ngWhite, fontSize: 12),
                        ),
                        backgroundColor: ngGreen,
                        behavior: SnackBarBehavior.floating,
                        shape: const RoundedRectangleBorder(),
                      ));
                    }
                  }
                },
              ),

            if (showLike)
              _MenuItem(
                icon: Icons.favorite,
                iconColor: lvm.isStagedLike(track.id) ? ngOrange : null,
                label: lvm.isStagedLike(track.id) ? 'Remove from Liked' : 'Like',
                onTap: () async {
                  Navigator.pop(context);
                  if (lvm.isStagedLike(track.id)) {
                    await lvm.removeStagedLike(track.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'Removed from liked tracks',
                          style: TextStyle(color: ngWhite, fontSize: 12),
                        ),
                        backgroundColor: ngBlack.withOpacity(0.9),
                        behavior: SnackBarBehavior.floating,
                        shape: const RoundedRectangleBorder(),
                      ));
                    }
                  } else {
                    await lvm.addStagedLike(track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'Added to liked tracks',
                          style: TextStyle(color: ngWhite, fontSize: 12),
                        ),
                        backgroundColor: ngGreen,
                        behavior: SnackBarBehavior.floating,
                        shape: const RoundedRectangleBorder(),
                      ));
                    }
                  }
                },
              ),

            if (showDislike)
              _MenuItem(
                icon: Icons.block,
                iconColor: ngRed,
                label: 'Never show again',
                onTap: () async {
                  Navigator.pop(context);
                  await lvm.addToBlacklist(track.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        'Added to blacklist',
                        style: TextStyle(color: ngWhite, fontSize: 12),
                      ),
                      backgroundColor: ngRed,
                      behavior: SnackBarBehavior.floating,
                      shape: const RoundedRectangleBorder(),
                    ));
                  }
                },
              ),

            if (showRemove && onRemove != null)
              _MenuItem(
                icon: Icons.delete_outline,
                iconColor: ngRed,
                label: 'Remove',
                onTap: () {
                  Navigator.pop(context);
                  onRemove();
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ngHairline.withOpacity(0.3))),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? ngWhite.withOpacity(0.8),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: ngHeaderFont,
                  fontSize: 14,
                  color: ngWhite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
