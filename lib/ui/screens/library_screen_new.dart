import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/playlist.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../widgets/ng_drawer.dart';
import '../widgets/track_artwork.dart';
import 'playlist_screen_new.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lvm = context.watch<LibraryViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const NgDrawer(),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              title: const Text('Library'),
              floating: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showCreatePlaylist(context),
                ),
              ],
            ),

            // Playlists
            if (lvm.playlists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.queue_music,
                        size: 64,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No playlists yet',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => _showCreatePlaylist(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Playlist'),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final playlist = lvm.playlists[index];
                      return FutureBuilder<List<PlaylistTrack>>(
                        future: lvm.getPlaylistTracks(playlist.id!),
                        builder: (context, snapshot) {
                          final tracks = snapshot.data ?? [];
                          final firstTrack =
                              tracks.isNotEmpty ? tracks.first.toTrack() : null;

                          return ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: firstTrack != null
                                  ? TrackArtwork(
                                      track: firstTrack,
                                      size: 48,
                                      radius: 8,
                                      compact: true,
                                      persistent: true,
                                    )
                                  : Icon(
                                      Icons.queue_music,
                                      color:
                                          colorScheme.onSecondaryContainer,
                                    ),
                            ),
                            title: Text(playlist.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (playlist.description != null)
                                  Text(
                                    playlist.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PlaylistScreen(playlist: playlist),
                                ),
                              );
                            },
                            onLongPress: () =>
                                _showPlaylistMenu(context, playlist),
                          );
                        },
                      );
                    },
                    childCount: lvm.playlists.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylist(BuildContext context) {
    final controller = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              final desc = descController.text.trim();
              final lvm = context.read<LibraryViewModel>();
              await lvm.createPlaylist(
                name,
                description: desc.isEmpty ? null : desc,
              );

              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created $name')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistMenu(BuildContext context, playlist) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenamePlaylist(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete playlist?'),
                    content: Text('Delete "${playlist.name}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && context.mounted) {
                  final lvm = context.read<LibraryViewModel>();
                  await lvm.deletePlaylist(playlist);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Playlist deleted')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenamePlaylist(BuildContext context, playlist) {
    final controller = TextEditingController(text: playlist.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              final lvm = context.read<LibraryViewModel>();
              if (playlist.id != null) {
                await lvm.renamePlaylist(playlist.id!, name);
              }

              if (context.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playlist renamed')),
                );
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
