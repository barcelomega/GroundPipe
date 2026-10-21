import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/artist_screen.dart';
import '../screens/player_screen_new.dart';
import '../../viewmodel/ng_viewmodel.dart';
import 'cache_pin_button.dart';
import 'track_artwork.dart';

/// Compact now-playing bar used above the main navigation and on pushed
/// screens such as the artist page.
class MiniPlayer extends StatelessWidget {
  /// Whether tapping the artist name opens the artist page. Disable this on
  /// the artist page itself so it does not push a duplicate route.
  final bool artistLinkEnabled;

  const MiniPlayer({super.key, this.artistLinkEnabled = false});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final track = vm.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final duration = vm.duration;
    final progress = (duration != null && duration.inMilliseconds > 0)
        ? (vm.position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  TrackArtwork(track: track, size: 48, compact: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (artistLinkEnabled)
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArtistScreen(
                                    authorUrl: track.artistAudioUrl,
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              track.artist,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          Text(
                            track.artist,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  CachePinButton(track: track),
                  IconButton(
                    tooltip: 'Previous track',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: vm.hasPrev() ? vm.playPrev : null,
                  ),
                  IconButton(
                    icon: Icon(
                      vm.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: vm.togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: vm.hasNext() ? vm.playNext : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
