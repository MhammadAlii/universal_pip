import 'package:flutter/material.dart';

import '../config/universal_pip_config.dart';

class DraggablePipOverlay extends StatefulWidget {
  const DraggablePipOverlay({
    required this.config,
    required this.child,
    this.bounds,
    this.onRectChanged,
    super.key,
  });

  final UniversalPipConfig config;
  final Widget child;
  final Rect? bounds;
  final ValueChanged<Rect>? onRectChanged;

  @override
  State<DraggablePipOverlay> createState() => _DraggablePipOverlayState();
}

class _DraggablePipOverlayState extends State<DraggablePipOverlay> {
  Offset? _offset;
  Offset? _dragStartOffset;
  Size _viewportSize = Size.zero;
  bool _isDragging = false;
  Rect? _lastReportedRect;

  @override
  void didUpdateWidget(covariant DraggablePipOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_didConfiguredSizeChange(oldWidget.config, widget.config)) {
      _offset = null;
      _dragStartOffset = null;
      _lastReportedRect = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

          final pipSize = _resolveSize();
          final offset = _clampOffset(_resolveOffset(pipSize), pipSize);
          _notifyRectChanged(context, offset, pipSize);

          return Stack(
            children: [
              AnimatedPositioned(
                duration: _isDragging
                    ? Duration.zero
                    : widget.config.animationDuration,
                curve: Curves.easeOut,
                left: offset.dx,
                top: offset.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {
                    _dragStartOffset = _offset ?? offset;
                    setState(() => _isDragging = true);
                  },
                  onPanUpdate: (details) {
                    final baseOffset = _dragStartOffset ?? _offset ?? offset;
                    final nextOffset = _clampOffset(
                      baseOffset + details.delta,
                      pipSize,
                    );
                    _dragStartOffset = nextOffset;
                    setState(() => _offset = nextOffset);
                    _notifyRectChanged(context, nextOffset, pipSize);
                  },
                  onPanEnd: (_) {
                    final nextOffset = widget.config.snapToEdge
                        ? _snapToEdge(_offset ?? offset, pipSize)
                        : _clampOffset(_offset ?? offset, pipSize);
                    setState(() {
                      _isDragging = false;
                      _dragStartOffset = null;
                      _offset = nextOffset;
                    });
                    _notifyRectChanged(context, nextOffset, pipSize);
                  },
                  child: SizedBox(
                    width: pipSize.width,
                    height: pipSize.height,
                    child: widget.child,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Size _resolveSize() {
    final configured = widget.config.initialSize;
    final maxSize = widget.config.maxSize;
    final width = configured.width.clamp(
      widget.config.minSize.width,
      maxSize?.width ?? double.infinity,
    );
    final height = configured.height.clamp(
      widget.config.minSize.height,
      maxSize?.height ?? double.infinity,
    );
    return Size(width.toDouble(), height.toDouble());
  }

  Offset _resolveOffset(Size pipSize) {
    if (_offset != null) return _offset!;

    final bounds = widget.bounds;
    if (bounds != null && _isSameSize(bounds.size, pipSize)) {
      return bounds.topLeft;
    }

    return _getInitialOffset(pipSize);
  }

  bool _didConfiguredSizeChange(
    UniversalPipConfig oldConfig,
    UniversalPipConfig newConfig,
  ) {
    return oldConfig.initialSize != newConfig.initialSize ||
        oldConfig.minSize != newConfig.minSize ||
        oldConfig.maxSize != newConfig.maxSize;
  }

  bool _isSameSize(Size a, Size b) {
    const tolerance = 0.5;
    return (a.width - b.width).abs() <= tolerance &&
        (a.height - b.height).abs() <= tolerance;
  }

  Offset _getInitialOffset(Size pipSize) {
    final padding = _effectiveSystemPadding();
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final maxX =
        (_viewportSize.width -
                pipSize.width -
                padding.right -
                widget.config.edgePadding)
            .clamp(padding.left + widget.config.edgePadding, double.infinity);
    final y =
        _viewportSize.height -
        pipSize.height -
        padding.bottom -
        widget.config.edgePadding;

    return Offset(
      direction == TextDirection.rtl
          ? padding.left + widget.config.edgePadding
          : maxX,
      y,
    );
  }

  Offset _clampOffset(Offset offset, Size pipSize) {
    final padding = _effectiveSystemPadding();
    final minX = padding.left + widget.config.edgePadding;
    final minY = padding.top + widget.config.edgePadding;
    final maxX =
        (_viewportSize.width -
                pipSize.width -
                padding.right -
                widget.config.edgePadding)
            .clamp(minX, double.infinity);
    final maxY =
        _viewportSize.height -
        pipSize.height -
        padding.bottom -
        widget.config.edgePadding;

    return Offset(
      offset.dx.clamp(minX, maxX).toDouble(),
      offset.dy.clamp(minY, maxY.clamp(minY, double.infinity)).toDouble(),
    );
  }

  Offset _snapToEdge(Offset offset, Size pipSize) {
    final clamped = _clampOffset(offset, pipSize);
    final padding = _effectiveSystemPadding();
    final minX = padding.left + widget.config.edgePadding;
    final maxX =
        (_viewportSize.width -
                pipSize.width -
                padding.right -
                widget.config.edgePadding)
            .clamp(minX, double.infinity);
    final targetX = clamped.dx < _viewportSize.width / 2 ? minX : maxX;
    return Offset(targetX.toDouble(), clamped.dy);
  }

  EdgeInsets _effectiveSystemPadding() {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return EdgeInsets.zero;

    final viewPadding = mediaQuery.viewPadding;
    final padding = mediaQuery.padding;
    final gestureInsets = mediaQuery.systemGestureInsets;

    return EdgeInsets.fromLTRB(
      _max3(viewPadding.left, padding.left, gestureInsets.left),
      _max3(viewPadding.top, padding.top, gestureInsets.top),
      _max3(viewPadding.right, padding.right, gestureInsets.right),
      _max3(viewPadding.bottom, padding.bottom, gestureInsets.bottom),
    );
  }

  double _max3(double a, double b, double c) {
    final maxAB = a > b ? a : b;
    return maxAB > c ? maxAB : c;
  }

  void _notifyRectChanged(BuildContext context, Offset offset, Size pipSize) {
    final onRectChanged = widget.onRectChanged;
    if (onRectChanged == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox) return;

      final globalPosition = renderObject.localToGlobal(offset);
      final rect = Rect.fromLTWH(
        globalPosition.dx,
        globalPosition.dy,
        pipSize.width,
        pipSize.height,
      );
      if (_lastReportedRect == rect) return;

      _lastReportedRect = rect;
      onRectChanged(rect);
    });
  }
}
