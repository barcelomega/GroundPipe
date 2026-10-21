import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../viewmodel/library_viewmodel.dart';

class CachePinButton extends StatefulWidget {
  final Track track;

  const CachePinButton({super.key, required this.track});

  @override
  State<CachePinButton> createState() => _CachePinButtonState();
}

class _CachePinButtonState extends State<CachePinButton> {
  Future<bool>? _cached;
  String? _trackId;
  int? _revision;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryViewModel>();
    final colors = Theme.of(context).colorScheme;
    if (_trackId != widget.track.id || _revision != library.cacheRevision) {
      _trackId = widget.track.id;
      _revision = library.cacheRevision;
      _cached = library.isTrackCached(widget.track.id);
    }
    final busy = library.isCacheBusy(widget.track.id);

    return FutureBuilder<bool>(
      key: ValueKey(widget.track.id),
      future: _cached,
      builder: (context, snapshot) {
        final cached = snapshot.data ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            IconButton(
              tooltip: cached ? 'Remove from cache' : 'Cache track',
              icon: Icon(
                cached ? Icons.push_pin : Icons.push_pin_outlined,
                color: busy
                    ? colors.onSurface.withOpacity(0.38)
                    : cached
                        ? colors.primary
                        : null,
              ),
              onPressed: busy || !snapshot.hasData
                  ? null
                  : () async {
                      final track = widget.track;
                      var success = false;
                      try {
                        success = cached
                            ? await library.removeCachedTrack(track.id)
                            : await library.cacheTrack(track) != null;
                      } catch (_) {
                        success = false;
                      }
                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(cached
                                  ? 'Could not remove track from cache'
                                  : 'Could not cache track. Please try again.')),
                        );
                      }
                    },
            ),
          ],
        );
      },
    );
  }
}
