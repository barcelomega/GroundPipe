import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../viewmodel/library_viewmodel.dart';
import 'add_to_playlist_sheet.dart';

/// Shows a context menu for a track.
Future<void> showTrackContextMenu(
  BuildContext context,
  Track track, {
  bool showAddToPlaylist = true,
  bool showLike = true,
  bool showDislike = true,
  bool showRemove = false,
  bool showCache = true,
  VoidCallback? onRemove,
}) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _TrackContextMenu(
      track: track,
      showAddToPlaylist: showAddToPlaylist,
      showLike: showLike,
      showDislike: showDislike,
      showRemove: showRemove,
      showCache: showCache,
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
  final bool showCache;
  final VoidCallback? onRemove;

  const _TrackContextMenu({
    required this.track,
    required this.showAddToPlaylist,
    required this.showLike,
    required this.showDislike,
    required this.showRemove,
    required this.showCache,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lvm = context.watch<LibraryViewModel>();
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with track info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  // Track icon
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: track.iconUrl.isNotEmpty
                        ? Image.network(
                            track.iconUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _DefaultIcon(colorScheme),
                          )
                        : _DefaultIcon(colorScheme),
                  ),
                  const SizedBox(width: 16),
                  // Track title and artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Actions
            if (showAddToPlaylist)
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to Playlist'),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added to \"${playlist.name}\"')),
                      );
                    }
                  }
                },
              ),

            if (showLike)
              ListTile(
                leading: Icon(
                  lvm.isStagedLike(track.id) ? Icons.favorite : Icons.favorite_border,
                  color: lvm.isStagedLike(track.id) ? Colors.red : null,
                ),
                title: Text(lvm.isStagedLike(track.id) ? 'Remove from Liked' : 'Like'),
                onTap: () async {
                  Navigator.pop(context);
                  if (lvm.isStagedLike(track.id)) {
                    await lvm.removeStagedLike(track.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Removed from liked tracks')),
                      );
                    }
                  } else {
                    await lvm.addStagedLike(track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to liked tracks')),
                      );
                    }
                  }
                },
              ),

            if (showDislike)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('Never show again'),
                onTap: () async {
                  Navigator.pop(context);
                  await lvm.addToBlacklist(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Added to blacklist'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () => lvm.removeFromBlacklist(track.id),
                        ),
                      ),
                    );
                  }
                },
              ),

            if (showCache)
              FutureBuilder<bool>(
                future: lvm.isCached(track.id),
                builder: (context, snapshot) {
                  final isCached = snapshot.data ?? false;
                  return ListTile(
                    leading: Icon(
                      isCached ? Icons.download_done : Icons.download,
                    ),
                    title: Text(isCached ? 'Remove from cache' : 'Cache offline'),
                    onTap: () async {
                      Navigator.pop(context);
                      if (isCached) {
                        await lvm.removeCachedTrack(track.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Removed from cache'),
                            ),
                          );
                        }
                      } else {
                        // Show progress dialog
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => _CacheProgressDialog(
                              track: track,
                              lvm: lvm,
                            ),
                          );
                        }
                      }
                    },
                  );
                },
              ),

              if (showRemove && onRemove != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove'),
                onTap: () {
                  Navigator.pop(context);
                  onRemove?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CacheProgressDialog extends StatefulWidget {
  final Track track;
  final LibraryViewModel lvm;

  const _CacheProgressDialog({required this.track, required this.lvm});

  @override
  State<_CacheProgressDialog> createState() => _CacheProgressDialogState();
}

class _CacheProgressDialogState extends State<_CacheProgressDialog> {
  double _progress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cacheTrack();
  }

  Future<void> _cacheTrack() async {
    try {
      final result = await widget.lvm.cacheTrack(
        widget.track,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      if (!mounted) return;

      if (result != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Track cached successfully')),
        );
      } else {
        setState(() {
          _error = 'Failed to cache track';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Caching track'),
      content: _error != null
          ? Text(_error!, style: const TextStyle(color: Colors.red))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 16),
                Text('${(_progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
      ],
    );
  }
}

class _DefaultIcon extends StatelessWidget {
  final ColorScheme colorScheme;
  const _DefaultIcon(this.colorScheme);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.music_note,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
