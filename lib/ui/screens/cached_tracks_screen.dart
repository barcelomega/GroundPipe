import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../widgets/track_list_item.dart';
import '../widgets/track_context_menu.dart';

class CachedTracksScreen extends StatefulWidget {
  const CachedTracksScreen({super.key});

  @override
  State<CachedTracksScreen> createState() => _CachedTracksScreenState();
}

class _CachedTracksScreenState extends State<CachedTracksScreen> {
  List<Track>? _cachedTracks;
  int? _totalSize;
  bool _isLoading = true;
  late final LibraryViewModel _library;
  late int _cacheRevision;

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryViewModel>();
    _cacheRevision = _library.cacheRevision;
    _library.addListener(_onLibraryChanged);
    _loadCachedTracks(backfill: true);
  }

  void _onLibraryChanged() {
    if (_cacheRevision == _library.cacheRevision) return;
    _cacheRevision = _library.cacheRevision;
    _loadCachedTracks();
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  Future<void> _loadCachedTracks({bool backfill = false}) async {
    final lvm = _library;
    final tracks = await lvm.getCachedTracks();
    final size = await lvm.getCacheSize();
    if (!mounted) return;
    setState(() {
      _cachedTracks = tracks;
      _totalSize = size;
      _isLoading = false;
    });
    if (!backfill) return;
    final changed = await lvm.backfillCachedArtwork();
    if (changed && mounted) await _loadCachedTracks();
  }

  @override
  Widget build(BuildContext context) {
    final lvm = context.read<LibraryViewModel>();
    final vm = context.read<NgViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final count = _cachedTracks?.length ?? 0;
    final sizeMB = ((_totalSize ?? 0) / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('Cached Tracks ($count) - ${sizeMB}MB'),
        actions: [
          if (count > 0)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear cache?'),
                    content: const Text(
                      'This will delete all cached audio files.',
                    ),
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

                if (confirm == true && mounted) {
                  await lvm.clearCache();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cache cleared')),
                    );
                  }
                }
              },
              child: const Text('Clear All'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(context, colorScheme, theme, lvm, vm),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    LibraryViewModel lvm,
    NgViewModel vm,
  ) {
    final cachedTracks = _cachedTracks ?? [];

    if (cachedTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No cached tracks',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pin tracks to cache them for offline playback',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: cachedTracks.length,
      itemBuilder: (context, index) {
        final track = cachedTracks[index];

        return TrackListItem(
          track: track,
          isLiked: lvm.isStagedLike(track.id),
          persistentArtwork: true,
          onTap: () {
            vm.setQueueContext(cachedTracks);
            vm.playTrack(track);
          },
          onLongPress: () => showTrackContextMenu(context, track),
        );
      },
    );
  }
}
