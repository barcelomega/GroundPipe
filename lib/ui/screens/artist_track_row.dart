import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../services/track_downloader.dart';
import '../../viewmodel/ng_viewmodel.dart';
import '../theme/ng_theme.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/ng_retro.dart';
import 'player_screen.dart';

class ArtistTrackRow extends StatefulWidget {
  final int index;
  final Track track;
  final List<Track> allTracks;
  final NgSkin skin;

  const ArtistTrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.allTracks,
    this.skin = NgSkin.gold,
  });

  @override
  State<ArtistTrackRow> createState() => _ArtistTrackRowState();
}

class _ArtistTrackRowState extends State<ArtistTrackRow> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NgViewModel>();
    final t = widget.track;
    final isActive = vm.currentTrack?.id == t.id;

    return NgAudioRow(
      index: widget.index,
      skin: widget.skin,
      iconUrl: t.aIconUrl,
      title: t.title,
      genre: t.genre,
      artist: '',
      playing: isActive,
      paused: isActive && !vm.isPlaying,
      onIconTap: () => isActive ? vm.togglePlayPause() : vm.playTrack(t),
      onTap: () {
        vm.setQueueContext(widget.allTracks);
        vm.playTrack(t);
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PlayerScreen()));
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t.duration > 0)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(_fmt(t.duration), style: ngLabel),
            ),
          NgIconButton(
            icon: 'more',
            padding: 5,
            tooltip: 'More options',
            onTap: () => showTrackContextMenu(
              context,
              t,
            ),
          ),
          NgIconButton(
            icon: 'download',
            padding: 5,
            tooltip: 'Download',
            onTap: _downloading
                ? null
                : () async {
                    setState(() => _downloading = true);
                    await TrackDownloader.download(t, context);
                    if (mounted) setState(() => _downloading = false);
                  },
          ),
        ],
      ),
    );
  }

  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class NgLoginPromptDialog extends StatelessWidget {
  final String message;
  final NgSkin skin;

  const NgLoginPromptDialog({
    super.key,
    required this.message,
    this.skin = NgSkin.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: NgPod(
        icon: 'user',
        title: 'Login Required',
        skin: skin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: ngBody),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NgButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 8),
                NgButton(
                  label: 'Log In',
                  icon: 'key',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
