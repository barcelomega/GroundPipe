import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../services/track_downloader.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../screens/artist_screen.dart';
import 'add_to_playlist_sheet.dart';
import 'track_artwork.dart';

/// Shows a context menu for a track.
Future<void> showTrackContextMenu(
  BuildContext context,
  Track track, {
  bool showRemove = false,
  bool showCache = true,
  VoidCallback? onRemove,
  String removeLabel = 'Remove from playlist',
}) async {
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (ctx) => _TrackContextMenu(
      track: track,
      showRemove: showRemove,
      showCache: showCache,
      onRemove: onRemove,
      removeLabel: removeLabel,
    ),
  );
}

class _TrackContextMenu extends StatelessWidget {
  final Track track;
  final bool showRemove;
  final bool showCache;
  final VoidCallback? onRemove;
  final String removeLabel;

  const _TrackContextMenu({
    required this.track,
    required this.showRemove,
    required this.showCache,
    this.onRemove,
    required this.removeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final lvm = context.watch<LibraryViewModel>();
    final colorScheme = Theme.of(context).colorScheme;
    final navigator = Navigator.of(context);

    return SafeArea(
      child: SingleChildScrollView(
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
                    TrackArtwork(
                      track: track,
                      size: 56,
                      radius: 8,
                      compact: true,
                      persistent: true,
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
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
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Open artist page'),
                onTap: () {
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ArtistScreen(authorUrl: track.artistAudioUrl),
                    ),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Add to playlist'),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  Navigator.pop(context);
                  final playlist = await showAddToPlaylistSheet(
                    navigator.context,
                    tracks: [track],
                    lvm: lvm,
                  );
                  if (playlist != null && navigator.mounted) {
                    await lvm.addTrackToPlaylist(playlist, track);
                    if (navigator.mounted) {
                      ScaffoldMessenger.of(navigator.context).showSnackBar(
                        SnackBar(content: Text('Added to "${playlist.name}"')),
                      );
                    }
                  }
                },
              ),

              ListTile(
                leading: Icon(
                  lvm.isStagedLike(track.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: lvm.isStagedLike(track.id) ? Colors.red : null,
                ),
                title: Text(lvm.isStagedLike(track.id)
                    ? 'Remove from Likes'
                    : 'Add to Likes'),
                onTap: () async {
                  Navigator.pop(context);
                  if (lvm.isStagedLike(track.id)) {
                    await lvm.removeStagedLike(track.id);
                    if (navigator.mounted) {
                      ScaffoldMessenger.of(navigator.context).showSnackBar(
                        const SnackBar(
                            content: Text('Removed from liked tracks')),
                      );
                    }
                  } else {
                    await lvm.addStagedLike(track);
                    if (navigator.mounted) {
                      ScaffoldMessenger.of(navigator.context).showSnackBar(
                        const SnackBar(content: Text('Added to liked tracks')),
                      );
                    }
                  }
                },
              ),

              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('Blacklist'),
                onTap: () async {
                  Navigator.pop(context);
                  await lvm.addToBlacklist(track);
                  if (navigator.mounted) {
                    ScaffoldMessenger.of(navigator.context).showSnackBar(
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
                        isCached ? Icons.push_pin : Icons.push_pin_outlined,
                        color: isCached ? colorScheme.primary : null,
                      ),
                      title: Text(
                          isCached ? 'Remove from cache' : 'Cache offline'),
                      onTap: () async {
                        Navigator.pop(context);
                        if (isCached) {
                          await lvm.removeCachedTrack(track.id);
                          if (navigator.mounted) {
                            ScaffoldMessenger.of(navigator.context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text('Removed from cache'),
                              ),
                            );
                          }
                        } else {
                          // Show progress dialog
                          if (navigator.mounted) {
                            showDialog(
                              context: navigator.context,
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

              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                  TrackDownloader.download(track, navigator.context);
                },
              ),

              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () async {
                  Navigator.pop(context);
                  final url =
                      'https://www.newgrounds.com/audio/listen/${track.id}';
                  try {
                    await const MethodChannel('ngmusic/share')
                        .invokeMethod<void>('shareText', {'text': url});
                  } on MissingPluginException {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (navigator.mounted) {
                      ScaffoldMessenger.of(navigator.context).showSnackBar(
                        const SnackBar(content: Text('Track link copied')),
                      );
                    }
                  }
                },
              ),

              if (showRemove && onRemove != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(removeLabel),
                  onTap: () {
                    Navigator.pop(context);
                    onRemove?.call();
                  },
                ),
            ],
          ),
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
