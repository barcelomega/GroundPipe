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

  const TrackArtwork({
    super.key,
    required this.track,
    required this.size,
    this.radius = 4,
    this.compact = false,
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
  bool _cachingIcon = false;

  @override
  Widget build(BuildContext context) {
    final revision = context.watch<LibraryViewModel>().cacheRevision;
    if (_trackId != widget.track.id ||
        _revision != revision ||
        _iconUrl != widget.track.iconUrl ||
        _coverPath != widget.track.localCoverPath) {
      _trackId = widget.track.id;
      _revision = revision;
      _iconUrl = widget.track.iconUrl;
      _coverPath = widget.track.localCoverPath;
      _cachingIcon = false;
      _localArtwork = _resolveLocalArtwork();
    }
    final colors = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.music_note,
      color: colors.onSurfaceVariant,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder<String?>(
          future: _localArtwork,
          builder: (context, snapshot) {
            final path = snapshot.data;
            if (path != null) {
              return Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                !widget.track.hasLocalIcon) {
              return ColoredBox(
                color: colors.surfaceContainerHighest,
                child: fallback,
              );
            }
            final urls = <String>{
              if (widget.compact)
                widget.track.aIconUrl
              else
                widget.track.coverUrl,
              ...widget.track.artworkUrls,
              widget.track.remoteIconUrl,
            }.where((url) => url.contains('://')).toList();
            if (urls.isEmpty) return fallback;
            return _FallbackArtwork(
              urls: urls,
              fallback: fallback,
              placeholderColor: colors.surfaceContainerHighest,
              onImageLoaded: widget.compact ? _cacheLoadedIcon : null,
            );
          },
        ),
      ),
    );
  }

  Future<String?> _resolveLocalArtwork() async {
    final track = widget.track;
    if (widget.compact) {
      final icon = await CacheManager.instance.getCachedIconPath(track.id);
      if (icon != null) return icon;
      if (track.hasLocalIcon && await File(track.localIconPath).exists()) {
        return track.localIconPath;
      }
      final cover = track.localCoverPath;
      if (cover != null && cover.isNotEmpty && await File(cover).exists()) {
        return cover;
      }
      return CacheManager.instance.getCachedArtworkPath(track.id);
    }
    final cover = track.localCoverPath;
    if (cover != null && cover.isNotEmpty && await File(cover).exists()) {
      return cover;
    }
    return CacheManager.instance.getCachedArtworkPath(track.id);
  }

  Future<void> _cacheLoadedIcon() async {
    if (_cachingIcon) return;
    _cachingIcon = true;
    try {
      final cache = CacheManager.instance;
      final path = cache.isPersistentArtworkTrack(widget.track.id)
          ? await cache.cachePermanentTrackIcon(widget.track)
          : await cache.cacheTemporaryTrackIcon(widget.track);
      if (mounted && path != null) {
        setState(() => _localArtwork = Future.value(path));
      }
    } catch (_) {
      // Artwork remains usable from the network image cache if disk caching fails.
    } finally {
      _cachingIcon = false;
    }
  }
}

/// Loads the first artwork URL that actually exists. Newgrounds generated
/// medium icons only for newer submissions, so older tracks need to fall back
/// to their plain icon or full cover instead of showing an empty tile.
class _FallbackArtwork extends StatefulWidget {
  final List<String> urls;
  final Widget fallback;
  final Color placeholderColor;
  final VoidCallback? onImageLoaded;

  const _FallbackArtwork({
    required this.urls,
    required this.fallback,
    required this.placeholderColor,
    this.onImageLoaded,
  });

  @override
  State<_FallbackArtwork> createState() => _FallbackArtworkState();
}

class _FallbackArtworkState extends State<_FallbackArtwork> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _FallbackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.isEmpty ||
        widget.urls.isEmpty ||
        oldWidget.urls.first != widget.urls.first) {
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
        widget.onImageLoaded?.call();
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
