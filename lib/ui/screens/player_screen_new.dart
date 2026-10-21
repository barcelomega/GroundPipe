import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import '../../viewmodel/ng_viewmodel.dart';
import '../../viewmodel/library_viewmodel.dart';
import '../../data/model/track.dart';
import '../../data/repository/ng_repository.dart';
import 'artist_screen.dart';
import '../widgets/cache_pin_button.dart';
import '../widgets/track_artwork.dart';
import '../widgets/add_to_playlist_sheet.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _repository = NgRepository();
  List<Track> _recommendations = const [];
  String? _recommendationsFor;
  bool _recommendationsLoading = false;
  bool _recommendationsUnavailable = false;
  int _recommendationsRequest = 0;
  NgViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<NgViewModel>()..addListener(_onPlayerChanged);
    _loadRecommendations(_viewModel?.currentTrack?.id);
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    final trackId = _viewModel?.currentTrack?.id;
    if (trackId != _recommendationsFor) _loadRecommendations(trackId);
  }

  Future<void> _loadRecommendations(String? trackId) async {
    final request = ++_recommendationsRequest;
    if (trackId == null) {
      if (!mounted) return;
      setState(() {
        _recommendationsFor = null;
        _recommendations = const [];
        _recommendationsLoading = false;
        _recommendationsUnavailable = false;
      });
      return;
    }

    setState(() {
      _recommendationsFor = trackId;
      _recommendations = const [];
      _recommendationsLoading = true;
      _recommendationsUnavailable = false;
    });
    try {
      final tracks = await _repository.fetchRecommendedTracks(trackId);
      if (!mounted || request != _recommendationsRequest) return;
      setState(() {
        _recommendations = tracks;
        _recommendationsLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _recommendationsRequest) return;
      setState(() {
        _recommendationsLoading = false;
        _recommendationsUnavailable = true;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatRatingStars(String? score) {
    if (score == null || score.isEmpty) return '';

    final rating = double.tryParse(score) ?? 0.0;
    final stars = rating.round();

    return '★' * stars.clamp(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final track = vm.currentTrack;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Player')),
        body: const Center(child: Text('No track playing')),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localArtwork = track.localCoverPath ??
        (track.hasLocalIcon ? track.localIconPath : null);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            SizedBox(
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (track.genre.isNotEmpty)
                        Text(
                          track.genre,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        '(${track.id})',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.expand_more),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CachePinButton(track: track),
                        Consumer<LibraryViewModel>(
                          builder: (context, library, _) => IconButton(
                            tooltip: library.isStagedLike(track.id)
                                ? 'Remove from Likes'
                                : 'Add to Likes',
                            icon: Icon(
                              library.isStagedLike(track.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: library.isStagedLike(track.id)
                                  ? colorScheme.error
                                  : null,
                            ),
                            onPressed: () async {
                              if (library.isStagedLike(track.id)) {
                                await library.removeStagedLike(track.id);
                              } else {
                                await library.addStagedLike(track);
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _showTrackMenu(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),

                      // Artwork
                      Hero(
                        tag: 'artwork_${track.id}',
                        child: Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: localArtwork != null
                                ? Image.file(
                                    File(localArtwork),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Icon(
                                        Icons.music_note,
                                        size: 96,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : track.iconUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: track.coverUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Center(
                                          child: Icon(
                                            Icons.music_note,
                                            size: 96,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) =>
                                            CachedNetworkImage(
                                          imageUrl: track.aIconUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Center(
                                            child: Icon(
                                              Icons.music_note,
                                              size: 96,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.music_note,
                                          size: 96,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Track info
                      Text(
                        track.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 8),

                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArtistScreen(authorUrl: track.artistAudioUrl),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text(
                            track.artist,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Rating display
                      if (track.score != null &&
                          track.score!.isNotEmpty &&
                          track.score != '0.00')
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatRatingStars(track.score),
                              style: TextStyle(
                                color: Colors.amber.shade700,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${track.score}/5)',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 24),

                      // Progress bar
                      Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16,
                              ),
                            ),
                            child: Slider(
                              value: vm.duration != null &&
                                      vm.duration!.inMilliseconds > 0
                                  ? (vm.position.inMilliseconds /
                                          vm.duration!.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                  : 0.0,
                              onChanged: (value) {
                                if (vm.duration != null) {
                                  final pos = Duration(
                                    milliseconds:
                                        (value * vm.duration!.inMilliseconds)
                                            .round(),
                                  );
                                  vm.seekTo(pos);
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(vm.position),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  _formatDuration(vm.duration ?? Duration.zero),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              vm.shuffle
                                  ? Icons.shuffle_on_outlined
                                  : Icons.shuffle,
                              color: vm.shuffle
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            onPressed: vm.toggleShuffle,
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.skip_previous),
                            iconSize: 36,
                            onPressed: vm.hasPrev() ? vm.playPrev : null,
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                vm.isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 32,
                              ),
                              onPressed: vm.togglePlayPause,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            iconSize: 36,
                            onPressed: vm.hasNext() ? vm.playNext : null,
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: Icon(
                              vm.repeat == 0
                                  ? Icons.repeat
                                  : vm.repeat == 1
                                      ? Icons.repeat_on_outlined
                                      : Icons.repeat_one_on_outlined,
                              color: vm.repeat != 0
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            onPressed: vm.cycleRepeat,
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Queue
                      _buildRecommendations(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_recommendationsLoading &&
        !_recommendationsUnavailable &&
        _recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'You might also enjoy',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_recommendationsLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_recommendationsUnavailable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Unavailable',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          ..._recommendations.take(5).map((track) {
            return ListTile(
              dense: true,
              leading: TrackArtwork(track: track, size: 40, compact: true),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              titleAlignment: ListTileTitleAlignment.center,
              onTap: () => vm.playTrack(track),
            );
          }),
      ],
    );
  }

  void _showTrackMenu(BuildContext context) {
    final vm = context.read<NgViewModel>();
    final track = vm.currentTrack;

    if (track == null) return;

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
                _showAddToPlaylist(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: implement download
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(ctx);
                _shareTrack(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareTrack(BuildContext context) async {
    final track = context.read<NgViewModel>().currentTrack;
    if (track == null) return;

    final url = 'https://www.newgrounds.com/audio/listen/${track.id}';
    try {
      await const MethodChannel('ngmusic/share').invokeMethod<void>(
        'shareText',
        {'text': url},
      );
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Track link copied to clipboard')),
        );
      }
    }
  }

  Future<void> _showAddToPlaylist(BuildContext context) async {
    final vm = context.read<NgViewModel>();
    final lvm = context.read<LibraryViewModel>();
    final track = vm.currentTrack;

    if (track == null) return;

    final playlist = await showAddToPlaylistSheet(
      context,
      tracks: [track],
      lvm: lvm,
    );
    if (playlist == null || !context.mounted) return;
    await lvm.addTrackToPlaylist(playlist, track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "${playlist.name}"')),
      );
    }
  }
}
