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
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

          final pipSize = _resolveSize();
          final offset = _clampOffset(
            _offset ?? widget.bounds?.topLeft ?? _getInitialOffset(pipSize),
            pipSize,
          );
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
    final configured = widget.bounds?.size ?? widget.config.initialSize;
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

  Offset _getInitialOffset(Size pipSize) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final padding = mediaQuery?.viewPadding ?? EdgeInsets.zero;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final maxX =
        (_viewportSize.width - pipSize.width - widget.config.edgePadding).clamp(
          widget.config.edgePadding,
          double.infinity,
        );
    final y =
        _viewportSize.height -
        pipSize.height -
        padding.bottom -
        widget.config.edgePadding;

    return Offset(
      direction == TextDirection.rtl ? widget.config.edgePadding : maxX,
      y,
    );
  }

  Offset _clampOffset(Offset offset, Size pipSize) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final padding = mediaQuery?.viewPadding ?? EdgeInsets.zero;
    final minY = padding.top + widget.config.edgePadding;
    final maxX =
        (_viewportSize.width - pipSize.width - widget.config.edgePadding).clamp(
          widget.config.edgePadding,
          double.infinity,
        );
    final maxY =
        _viewportSize.height -
        pipSize.height -
        padding.bottom -
        widget.config.edgePadding;

    return Offset(
      offset.dx.clamp(widget.config.edgePadding, maxX).toDouble(),
      offset.dy.clamp(minY, maxY.clamp(minY, double.infinity)).toDouble(),
    );
  }

  Offset _snapToEdge(Offset offset, Size pipSize) {
    final clamped = _clampOffset(offset, pipSize);
    final maxX =
        (_viewportSize.width - pipSize.width - widget.config.edgePadding).clamp(
          widget.config.edgePadding,
          double.infinity,
        );
    final targetX = clamped.dx < _viewportSize.width / 2
        ? widget.config.edgePadding
        : maxX;
    return Offset(targetX.toDouble(), clamped.dy);
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
