import 'package:flutter/material.dart';

import '../../data/model/playlist.dart';
import '../../data/model/track.dart';
import '../../viewmodel/library_viewmodel.dart';

/// Shows a bottom sheet to select a playlist for adding tracks.
/// Returns the selected playlist, or null if cancelled.
Future<Playlist?> showAddToPlaylistSheet(
  BuildContext context, {
  required List<Track> tracks,
  required LibraryViewModel lvm,
}) async {
  return showModalBottomSheet<Playlist>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _AddToPlaylistSheet(tracks: tracks, lvm: lvm),
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  final List<Track> tracks;
  final LibraryViewModel lvm;

  const _AddToPlaylistSheet({required this.tracks, required this.lvm});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  bool _creating = false;
  bool _isCreatingPlaylist = false;
  String? _createError;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = widget.lvm.playlists;
    final colorScheme = Theme.of(context).colorScheme;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.of(context).size.height - bottomInset;

    return SafeArea(
      child: SizedBox(
        height: availableHeight * 0.8,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  widget.tracks.length == 1
                      ? 'Add to Playlist'
                      : 'Add ${widget.tracks.length} tracks to Playlist',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),

              // Create new playlist
              if (_creating)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Playlist name',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _createAndSelect(),
                      ),
                      if (_createError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _createError!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _creating = false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed:
                                  _isCreatingPlaylist ? null : _createAndSelect,
                              icon: _isCreatingPlaylist
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add),
                              label: Text(_isCreatingPlaylist
                                  ? 'Creating...'
                                  : 'Create'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                ListTile(
                  leading: Icon(Icons.add_circle_outline,
                      color: colorScheme.primary),
                  title: Text(
                    'Create new playlist',
                    style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500),
                  ),
                  onTap: () => setState(() => _creating = true),
                ),

              const Divider(height: 1),

              // Playlist list
              Expanded(
                child: playlists.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No playlists yet',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (ctx, i) => ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          title: Text(playlists[i].name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, playlists[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createAndSelect() async {
    if (_isCreatingPlaylist) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isCreatingPlaylist = true;
      _createError = null;
    });
    try {
      final playlist = await widget.lvm.createPlaylist(name);
      if (mounted) Navigator.pop(context, playlist);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCreatingPlaylist = false;
        _createError = 'Could not create playlist. Please try again.';
      });
    }
  }
}
