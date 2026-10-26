import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/model/track.dart';
import '../../data/repository/cache_manager.dart';
import '../../viewmodel/library_viewmodel.dart';

/// Track artwork that prefers the locally cached cover when available.
class TrackArtwork extends StatefulWidget {
  final Track track;
  final double size;
  final double radius;

  /// Uses the reduced cached icon when [compact] is true.
  final bool compact;

  /// Forces the icon into the permanent store, for lists whose tracks belong
  /// to Likes, playlists, Timeline or recommendations.
  final bool persistent;

  /// Optional placeholder shown while the artwork is unavailable. Retro
  /// screens pass their own default audio icon.
  final Widget? fallback;

  const TrackArtwork({
    super.key,
    required this.track,
    required this.size,
    this.radius = 4,
    this.compact = false,
    this.persistent = false,
    this.fallback,
  });

  @override
  State<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends State<TrackArtwork> {
  Future<String?>? _localArtwork;
  String? _trackId;
  String? _iconUrl;
  String? _coverPath;
  int? _revision;
  String? _initialPath;

  @override
  Widget build(BuildContext context) {
    final revision = context.watch<LibraryViewModel>().cacheRevision;
    
    // Track what changed
    final trackIdChanged = _trackId != widget.track.id;
    final revisionChanged = _revision != revision;
    final coverPathChanged = _coverPath != widget.track.localCoverPath;
    final iconUrlChanged = _iconUrl != widget.track.iconUrl;
    
    if (trackIdChanged || revisionChanged || coverPathChanged || iconUrlChanged) {
      _trackId = widget.track.id;
      _revision = revision;
      _iconUrl = widget.track.iconUrl;
      _coverPath = widget.track.localCoverPath;
      
      // Only recreate the future if something other than iconUrl changed.
      // If only iconUrl changed, _FallbackArtwork will pick it up automatically
      // from widget.track without flashing a placeholder.
      if (trackIdChanged || revisionChanged || coverPathChanged) {
        final known = _knownLocalPath();
        _initialPath = known;
        _localArtwork =
            known != null ? Future.value(known) : _resolveLocalArtwork();
      }
    }
    final colors = Theme.of(context).colorScheme;
    final fallback = widget.fallback ??
        Icon(
          Icons.music_note,
          color: colors.onSurfaceVariant,
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<String?>(
          future: _localArtwork,
          initialData: _initialPath,
          builder: (context, snapshot) {
            final path = snapshot.data;
            if (path != null) {
              final dpr =
                  MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
              return Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: (widget.size * dpr).round(),
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: fallback,
                  );
                },
                errorBuilder: (_, __, ___) => fallback,
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ColoredBox(
                color: colors.surfaceContainerHighest,
                child: fallback,
              );
            }
            if (widget.compact) {
              // Icons live only in CacheManager's artwork store; never let
              // the generic network-image cache own them.
              return fallback;
            }
            final urls = <String>{
              widget.track.coverUrl,
              ...widget.track.artworkUrls,
              widget.track.remoteIconUrl,
              if (widget.track.hasLocalIcon)
                ...widget.track.remoteArtworkUrls,
            }.where((url) => url.contains('://')).toList();
            if (urls.isEmpty) return fallback;
            return _FallbackArtwork(
              urls: urls,
              fallback: fallback,
              placeholderColor: colors.surfaceContainerHighest,
            );
          },
        ),
      ),
    );
  }

  /// Synchronous local lookup used before the first frame, so reopening a
  /// screen does not flash a placeholder while the same path is resolved
  /// asynchronously.
  String? _knownLocalPath() {
    final track = widget.track;
    if (widget.compact) {
      final icon = CacheManager.instance.knownIconPath(track.id);
      if (icon != null) return icon;
      if (track.hasLocalIcon && File(track.localIconPath).existsSync()) {
        return track.localIconPath;
      }
      final cover = track.localCoverPath;
      if (cover != null && cover.isNotEmpty && File(cover).existsSync()) {
        return cover;
      }
      return CacheManager.instance.knownArtworkPath(track.id);
    }
    final cover = track.localCoverPath;
    if (cover != null && cover.isNotEmpty && File(cover).existsSync()) {
      return cover;
    }
    return CacheManager.instance.knownArtworkPath(track.id);
  }

  Future<String?> _resolveLocalArtwork() async {
    final track = widget.track;
    if (widget.compact) {
      final known = _knownLocalPath();
      if (known != null) return known;
      final icon = await CacheManager.instance.getCachedIconPath(track.id);
      if (icon != null) return icon;
      if (track.hasLocalIcon && await File(track.localIconPath).exists()) {
        return track.localIconPath;
      }
      final cover = track.localCoverPath;
      if (cover != null && cover.isNotEmpty && await File(cover).exists()) {
        return cover;
      }
      return CacheManager.instance.resolveTrackIcon(
        track,
        persistent: widget.persistent ||
            CacheManager.instance.isPersistentArtworkTrack(track.id),
      );
    }
    final cover = track.localCoverPath;
    if (cover != null && cover.isNotEmpty && await File(cover).exists()) {
      return cover;
    }
    return CacheManager.instance.getCachedArtworkPath(track.id);
  }
}

/// Loads the first artwork URL that actually exists. Newgrounds generated
/// medium icons only for newer submissions, so older tracks need to fall back
/// to their plain icon or full cover instead of showing an empty tile.
class _FallbackArtwork extends StatefulWidget {
  final List<String> urls;
  final Widget fallback;
  final Color placeholderColor;

  const _FallbackArtwork({
    required this.urls,
    required this.fallback,
    required this.placeholderColor,
  });

  @override
  State<_FallbackArtwork> createState() => _FallbackArtworkState();
}

class _FallbackArtworkState extends State<_FallbackArtwork> {
  int _index = 0;
  bool _loaded = false;

  @override
  void didUpdateWidget(covariant _FallbackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reset if we haven't loaded anything yet and the URL list changed
    if (!_loaded &&
        (oldWidget.urls.isEmpty ||
            widget.urls.isEmpty ||
            oldWidget.urls.first != widget.urls.first)) {
      _index = 0;
    }
  }

  void _tryNext() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _index++);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.urls.length) return widget.fallback;
    return CachedNetworkImage(
      imageUrl: widget.urls[_index],
      fit: BoxFit.cover,
      imageBuilder: (context, imageProvider) {
        _loaded = true;
        return Image(image: imageProvider, fit: BoxFit.cover);
      },
      placeholder: (_, __) => ColoredBox(
        color: widget.placeholderColor,
        child: widget.fallback,
      ),
      errorWidget: (_, __, ___) {
        _tryNext();
        return ColoredBox(
          color: widget.placeholderColor,
          child: widget.fallback,
        );
      },
    );
  }
}
