import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../widgets/track_list_item.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/mini_player.dart';
import '../../viewmodel/authors_viewmodel.dart';

enum _LikesMenuAction { import, clear }

class StagedLikesScreen extends StatefulWidget {
  const StagedLikesScreen({super.key});

  @override
  State<StagedLikesScreen> createState() => _StagedLikesScreenState();
}

class _StagedLikesScreenState extends State<StagedLikesScreen> {
  bool _importing = false;

  Future<void> _showImportDialog() async {
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ImportLikesDialog(),
    );
    if (username == null || username.isEmpty || !mounted) return;
    await _importLikes(username);
  }

  Future<void> _importLikes(String username) async {
    if (_importing) return;
    final lvm = context.read<LibraryViewModel>();
    setState(() => _importing = true);
    try {
      final result = await lvm.importLikes(username);
      if (!mounted) return;
      final message = result.tooManyFavorites
          ? 'Skipped $username: 1000 or more favorites'
          : result.countUnavailable
              ? 'Could not read $username\'s favorites count'
              : result.added > 0
                  ? 'Imported ${result.added} '
                      '${result.added == 1 ? 'like' : 'likes'}'
                  : result.found == 0
                      ? 'No likes found for $username'
                      : 'No new likes to import';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import likes: $message')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmClearLikes() async {
    final lvm = context.read<LibraryViewModel>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Likes'),
        content: const Text('Remove all liked tracks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await lvm.clearStagedLikes();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Likes cleared')),
    );
  }

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
          PopupMenuButton<_LikesMenuAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Likes options',
            enabled: !_importing,
            onSelected: (action) {
              if (action == _LikesMenuAction.import) {
                _showImportDialog();
              } else {
                _confirmClearLikes();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _LikesMenuAction.import,
                child: _LikesMenuRow(
                  icon: Icons.download_outlined,
                  label: 'Import Likes',
                ),
              ),
              PopupMenuItem(
                value: _LikesMenuAction.clear,
                enabled: lvm.stagedLikes.isNotEmpty,
                child: const _LikesMenuRow(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Clear Likes',
                ),
              ),
            ],
          ),
        ],
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
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
                  persistentArtwork: true,
                  onTap: () {
                    final trackList = likes.map((l) => l.toTrack()).toList();
                    vm.setQueueContext(trackList);
                    vm.playTrack(track);
                  },
                  onLongPress: () => showTrackContextMenu(context, track),
                );
              },
            ),
      bottomNavigationBar: vm.currentTrack == null
          ? null
          : const SafeArea(
              top: false,
              child: MiniPlayer(),
            ),
    );
  }
}

class _ImportLikesDialog extends StatefulWidget {
  const _ImportLikesDialog();

  @override
  State<_ImportLikesDialog> createState() => _ImportLikesDialogState();
}

class _ImportLikesDialogState extends State<_ImportLikesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Likes'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          hintText: 'Enter your Newgrounds username...',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (_, value, __) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: const Text('Import'),
          ),
        ),
      ],
    );
  }
}

class _LikesMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LikesMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
