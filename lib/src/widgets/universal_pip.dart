import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/universal_pip_config.dart';
import '../controller/universal_pip_controller.dart';
import '../controller/universal_pip_state.dart';
import '../models/native_pip_content.dart';
import 'draggable_pip_overlay.dart';
import 'native_pip_content_surface.dart';

typedef UniversalPipBuilder =
    Widget Function(BuildContext context, UniversalPipState state);

typedef NativePipContentBuilder =
    NativePipContent? Function(BuildContext context, UniversalPipState state);

typedef NativePipSurfaceBuilder =
    Widget Function(
      BuildContext context,
      UniversalPipState state,
      NativePipContent content,
    );

class UniversalPip extends StatefulWidget {
  const UniversalPip({
    required this.controller,
    required this.inAppBuilder,
    required this.child,
    this.config = const UniversalPipConfig(),
    this.nativeContentBuilder,
    this.nativeSurfaceBuilder,
    super.key,
  });

  final UniversalPipController controller;
  final UniversalPipConfig config;
  final UniversalPipBuilder inAppBuilder;
  final NativePipContentBuilder? nativeContentBuilder;
  final NativePipSurfaceBuilder? nativeSurfaceBuilder;
  final Widget child;

  @override
  State<UniversalPip> createState() => _UniversalPipState();
}

class _UniversalPipState extends State<UniversalPip>
    with WidgetsBindingObserver {
  bool _isAutoEnteringSystemPip = false;
  bool _isPreparingSystemPip = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant UniversalPip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!widget.controller.state.isSystemPipActive) {
        widget.controller.restoreInAppPip();
      }
      return;
    }

    final nativePipEnabled =
        widget.config.enableSystemPip || widget.config.enableWebDocumentPip;
    if (!nativePipEnabled ||
        !widget.config.autoEnterSystemPip ||
        !widget.controller.state.isVisible) {
      return;
    }

    final shouldEnter =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused;
    if (shouldEnter) {
      unawaited(_enterSystemPipFromLifecycle());
    }
  }

  Future<void> _enterSystemPipFromLifecycle() async {
    if (_isAutoEnteringSystemPip) return;

    _isAutoEnteringSystemPip = true;
    try {
      await widget.controller.enterSystemPip(
        aspectRatio: widget.config.aspectRatio,
        preRenderSystemSurface:
            widget.config.preRenderSystemSurfaceBeforeSystemPip,
        androidSeamlessResize: widget.config.androidSeamlessResize,
        androidAutoEnterOnUserLeave: widget.config.androidAutoEnterOnUserLeave,
      );
    } finally {
      _isAutoEnteringSystemPip = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final content =
        widget.nativeContentBuilder?.call(context, state) ?? state.content;
    final showSystemSurface =
        content != null && _shouldShowSystemSurface(state);

    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (state.isTransitioning && widget.config.transitionBlurSigma > 0)
            _buildTransitionBackdrop(),
          if (showSystemSurface)
            _buildSystemSurfaceOverlay(context, state, content),
          if (state.showInAppPip && !showSystemSurface)
            DraggablePipOverlay(
              config: widget.config,
              bounds: state.bounds ?? widget.config.initialBounds,
              onRectChanged: widget.controller.setBounds,
              child: ClipRRect(
                borderRadius: widget.config.borderRadius,
                child: widget.inAppBuilder(context, state),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransitionBackdrop() {
    final blurSigma = widget.config.transitionBlurSigma;
    return Positioned.fill(
      child: IgnorePointer(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
    );
  }

  Widget _buildSystemSurfaceOverlay(
    BuildContext context,
    UniversalPipState state,
    NativePipContent content,
  ) {
    final surface = _buildTransitionAwareSystemSurface(context, state, content);

    final transitionBounds = _surfaceBoundsFor(state);
    if (transitionBounds == null) {
      return Positioned.fill(child: surface);
    }

    return Positioned.fromRect(
      rect: transitionBounds,
      child: ClipRRect(
        borderRadius: widget.config.borderRadius,
        child: surface,
      ),
    );
  }

  Widget _buildTransitionAwareSystemSurface(
    BuildContext context,
    UniversalPipState state,
    NativePipContent content,
  ) {
    final surface = _buildSystemSurface(context, state, content);
    if (!state.isTransitioning || widget.config.transitionBlurSigma <= 0) {
      return surface;
    }

    final blurSigma = widget.config.transitionBlurSigma * 0.45;
    return ColoredBox(
      color: Colors.black,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      ),
    );
  }

  Rect? _surfaceBoundsFor(UniversalPipState state) {
    final bounds = state.bounds;
    if (!_shouldUseBoundedSystemSurface(state) || bounds == null) return null;
    if (bounds.isEmpty || !bounds.isFinite) return null;
    return bounds;
  }

  Widget _buildSystemSurface(
    BuildContext context,
    UniversalPipState state,
    NativePipContent content,
  ) {
    final builder = widget.nativeSurfaceBuilder;
    if (builder != null) {
      return builder(context, state, content);
    }
    return NativePipContentSurface(content: content);
  }

  bool _shouldShowSystemSurface(UniversalPipState state) {
    if (state.isTransitioning) return true;
    return state.isSystemPipActive &&
        defaultTargetPlatform == TargetPlatform.android;
  }

  bool _shouldUseBoundedSystemSurface(UniversalPipState state) {
    return state.isTransitioning;
  }

  void _handleControllerChanged() {
    unawaited(_prepareAndroidSystemPip());
    if (mounted) setState(() {});
  }

  Future<void> _prepareAndroidSystemPip() async {
    if (_isPreparingSystemPip) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!widget.config.enableSystemPip) return;
    if (!widget.controller.state.isVisible) return;

    _isPreparingSystemPip = true;
    try {
      await widget.controller.prepareSystemPip(
        aspectRatio: widget.config.aspectRatio,
        androidSeamlessResize: widget.config.androidSeamlessResize,
        androidAutoEnterOnUserLeave: widget.config.androidAutoEnterOnUserLeave,
      );
    } finally {
      _isPreparingSystemPip = false;
    }
  }
}
