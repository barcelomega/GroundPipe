import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../data/model/track.dart';
import '../../data/repository/waveform_cache.dart';

/// A waveform progress bar that loads audio peaks from Newgrounds
/// and displays them with progress overlay.
class WaveformProgress extends StatefulWidget {
  final Track track;
  final double progress; // 0.0 to 1.0
  final ValueChanged<double>? onSeek;

  const WaveformProgress({
    super.key,
    required this.track,
    required this.progress,
    this.onSeek,
  });

  @override
  State<WaveformProgress> createState() => _WaveformProgressState();
}

class _WaveformProgressState extends State<WaveformProgress> {
  ui.Image? _waveformImage;
  String? _lastPeaksUrl;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _lastPeaksUrl = widget.track.peaksUrl;
    // Reopening the player for the same track reuses the decoded image, so
    // the waveform is painted on the first frame instead of flashing the
    // fallback slider while the PNG is read again.
    _waveformImage = WaveformImageCache.instance.known(widget.track.id);
    if (_waveformImage == null) _loadWaveform();
  }

  @override
  void didUpdateWidget(WaveformProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if track changed OR if peaksUrl became available/changed
    final currentPeaksUrl = widget.track.peaksUrl;
    if (oldWidget.track.id != widget.track.id ||
        (_lastPeaksUrl != currentPeaksUrl && currentPeaksUrl != null)) {
      _lastPeaksUrl = currentPeaksUrl;
      final previous = _waveformImage;
      _waveformImage = WaveformImageCache.instance.known(widget.track.id);
      previous?.dispose();
      if (_waveformImage == null) _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    final gen = ++_loadGen;
    final image = await WaveformImageCache.instance.load(widget.track);
    if (gen != _loadGen || !mounted) {
      image?.dispose();
      return;
    }
    if (image == null) return;
    final previous = _waveformImage;
    setState(() {
      _waveformImage = image;
    });
    previous?.dispose();
  }

  @override
  void dispose() {
    _waveformImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show waveform if loaded, otherwise show fallback slider
    if (_waveformImage != null) {
      return GestureDetector(
      onTapDown: (details) {
        if (widget.onSeek == null) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = details.localPosition.dx;
        final progress = (localX / box.size.width).clamp(0.0, 1.0);
        widget.onSeek!(progress);
      },
      onHorizontalDragUpdate: (details) {
        if (widget.onSeek == null) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localX = details.localPosition.dx;
        final progress = (localX / box.size.width).clamp(0.0, 1.0);
        widget.onSeek!(progress);
      },
      child: CustomPaint(
        painter: _WaveformPainter(
          image: _waveformImage!,
          progress: widget.progress.clamp(0.0, 1.0),
          activeColor: colorScheme.primary,
          inactiveColor: colorScheme.onSurfaceVariant.withOpacity(0.3),
        ),
        size: const Size(double.infinity, 48),
      ),
    );
    }
    
    // Fallback slider (shown while loading or on error)
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      child: Slider(
        value: widget.progress.clamp(0.0, 1.0),
        onChanged: widget.onSeek,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final ui.Image image;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.image,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  /// Tints the peaks image with [color], using the source luminance as alpha.
  ///
  /// Flutter's color matrix operates on unpremultiplied colors, so RGB is a
  /// constant (the translation column) and alpha comes from the luminance,
  /// scaled by the color's own opacity.
  static ColorFilter _tint(Color color) {
    final a = color.opacity;
    return ColorFilter.matrix(<double>[
      0, 0, 0, 0, color.red.toDouble(),
      0, 0, 0, 0, color.green.toDouble(),
      0, 0, 0, 0, color.blue.toDouble(),
      0.299 * a, 0.587 * a, 0.114 * a, 0, 0,
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Draw the whole waveform in the inactive color. The image itself carries
    // the alpha (via its luminance), so there is no separate fill rect that
    // could leak past the mask at fractional device-pixel edges.
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()
        ..colorFilter = _tint(inactiveColor)
        ..filterQuality = FilterQuality.medium,
    );

    // Overlay the played portion in the active color.
    if (progress > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      canvas.drawImageRect(
        image,
        srcRect,
        dstRect,
        Paint()
          ..colorFilter = _tint(activeColor)
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
