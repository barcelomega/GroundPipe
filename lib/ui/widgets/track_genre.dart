import 'package:flutter/material.dart';

import '../../data/model/track.dart';
import '../../data/repository/ng_repository.dart';

class TrackGenre extends StatefulWidget {
  final Track track;

  const TrackGenre({super.key, required this.track});

  @override
  State<TrackGenre> createState() => _TrackGenreState();
}

class _TrackGenreState extends State<TrackGenre> {
  late Future<String> _genre;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _genre = NgRepository().resolveTrackGenre(widget.track);

  @override
  void didUpdateWidget(covariant TrackGenre oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _genre,
        initialData: widget.track.genreVerified ? widget.track.genre : null,
        builder: (context, snapshot) {
          final genre = snapshot.data ?? '';
          if (genre.isEmpty) return const SizedBox.shrink();
          return Tooltip(
            message: genre,
            child: Text(
              genre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        },
      );
}
