import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/universal_pip_config.dart';
import '../controller/universal_pip_controller.dart';
import '../controller/universal_pip_state.dart';
import '../models/native_pip_content.dart';
import 'draggable_pip_overlay.dart';
import 'native_pip_content_surface.dart';

typedef UniversalPipBuilder =
    Widget Function(BuildContext context, UniversalPipState state);

typedef WebPipBuilder =
    Widget Function(BuildContext context, UniversalPipState state);

typedef WebDocumentPipDomBuilder =
    void Function(Object pipWindow, UniversalPipState state);

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
    this.webInAppBuilder,
    this.webDocumentPipDomBuilder,
    this.nativeSurfaceBuilder,
    super.key,
  });

  final UniversalPipController controller;
  final UniversalPipConfig config;

  /// Builds the draggable Flutter PiP shown inside the app.
  final UniversalPipBuilder inAppBuilder;

  /// Builds the draggable Flutter PiP inside the browser tab on web.
  ///
  /// Falls back to [inAppBuilder] when omitted.
  final WebPipBuilder? webInAppBuilder;

  /// Renders content inside the separate browser Document PiP window.
  ///
  /// This receives a browser-specific window object on web. It must create DOM
  /// content rather than Flutter widgets because the window has its own DOM.
  final WebDocumentPipDomBuilder? webDocumentPipDomBuilder;

  /// Builds the Flutter preview surface used during native/system PiP handoff.
  final NativePipSurfaceBuilder? nativeSurfaceBuilder;

  final Widget child;

  @override
  State<UniversalPip> createState() => _UniversalPipState();
}

class _UniversalPipState extends State<UniversalPip>
    with WidgetsBindingObserver {
  bool _isAutoEnteringSystemPip = false;
  bool _isPreparingSystemPip = false;
  bool _hasPendingSystemPipPreparation = false;
  bool _navigatorCanHandlePop = false;
  Object? _lastWebDocumentPipWindow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_handleControllerChanged);
    _configureWebAutoEntry();
  }

  @override
  void didUpdateWidget(covariant UniversalPip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    _configureWebAutoEntry();
    if (oldWidget.config.enterSystemPipOnBack !=
            widget.config.enterSystemPipOnBack ||
        oldWidget.config.enableSystemPip != widget.config.enableSystemPip) {
      _syncFrameworkHandlesBack();
    }
  }

  bool get _handlesBackForSystemPip {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final state = widget.controller.state;
    return widget.config.enterSystemPipOnBack &&
        widget.config.enableSystemPip &&
        state.isInApp &&
        !state.isSystemPipActive &&
        !state.isTransitioning;
  }

  bool _handleNavigationNotification(NavigationNotification notification) {
    _navigatorCanHandlePop = notification.canHandlePop;
    if (!widget.config.enterSystemPipOnBack) return false;
    _syncFrameworkHandlesBack();
    return true;
  }

  void _syncFrameworkHandlesBack() {
    if (!widget.config.enterSystemPipOnBack) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.detached) return;
    SystemNavigator.setFrameworkHandlesBack(
      _navigatorCanHandlePop || _handlesBackForSystemPip,
    );
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_handlesBackForSystemPip || _navigatorCanHandlePop) return false;
    return widget.controller.enterSystemPip(
      aspectRatio: widget.config.aspectRatio,
      preRenderSystemSurface:
          widget.config.preRenderSystemSurfaceBeforeSystemPip,
      androidSeamlessResize: widget.config.androidSeamlessResize,
      androidAutoEnterOnUserLeave: widget.config.androidAutoEnterOnUserLeave,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChanged);
    widget.controller.setWebAutoEnterHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Chrome invokes the registered Media Session action when Auto PiP is
    // available; ordinary browser lifecycle events cannot create the window.
    if (kIsWeb) return;

    if (state == AppLifecycleState.resumed) {
      if (widget.controller.state.isSystemPipActive &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        unawaited(_exitSystemPipAndRestore());
        return;
      }
      if (widget.controller.state.mode == UniversalPipMode.system ||
          widget.controller.state.isTransitioning) {
        widget.controller.restoreAfterSystemPipExit();
      }
      return;
    }

    final nativePipEnabled = widget.config.enableSystemPip;
    if (!nativePipEnabled ||
        !widget.config.autoEnterSystemPip ||
        !widget.controller.state.isVisible ||
        widget.controller.state.isSystemPipActive ||
        widget.controller.state.isTransitioning) {
      return;
    }

    // `inactive` fires for any transient loss of focus while the app stays
    // fully visible (notification shade, quick settings, a system dialog,
    // an incoming-call overlay, etc.) — treating it as "user is leaving"
    // caused PiP to trigger on those too. `hidden`/`paused` only fire once
    // the app is actually no longer visible, which is what auto-enter
    // should key off.
    final shouldEnter =
        state == AppLifecycleState.hidden || state == AppLifecycleState.paused;
    if (shouldEnter) {
      unawaited(_enterSystemPipFromLifecycle());
    }
  }

  Future<void> _enterSystemPipFromLifecycle() async {
    if (_isAutoEnteringSystemPip) {
      return;
    }

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

  void _configureWebAutoEntry() {
    if (!kIsWeb) return;

    final shouldRegister =
        widget.config.enableWebDocumentPip &&
        widget.config.autoEnterSystemPip &&
        widget.webDocumentPipDomBuilder != null;
    widget.controller.setWebAutoEnterHandler(
      shouldRegister ? _enterWebDocumentPipFromBrowser : null,
    );
  }

  Future<void> _enterWebDocumentPipFromBrowser() async {
    final state = widget.controller.state;
    if (!state.isVisible || state.isSystemPipActive || state.isTransitioning) {
      return;
    }

    await widget.controller.enterSystemPip(
      aspectRatio: widget.config.aspectRatio,
      preRenderSystemSurface: false,
    );
  }

  Future<void> _exitSystemPipAndRestore() async {
    await widget.controller.exitSystemPip();
    widget.controller.restoreAfterSystemPipExit();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final content = state.content;
    final showSystemSurface =
        content != null && _shouldShowSystemSurface(state);
    final showWebDocumentSurface = _shouldShowWebDocumentSurface(state);

    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<NavigationNotification>(
            onNotification: _handleNavigationNotification,
            child: widget.child,
          ),
          if (state.isTransitioning && widget.config.transitionBlurSigma > 0)
            _buildTransitionBackdrop(),
          if (showSystemSurface)
            _buildSystemSurfaceOverlay(context, state, content),
          if (showWebDocumentSurface)
            _buildWebDocumentSurfaceOverlay(context, state),
          if (state.showInAppPip &&
              !showSystemSurface &&
              !showWebDocumentSurface)
            DraggablePipOverlay(
              config: widget.config,
              bounds: state.bounds ?? widget.config.initialBounds,
              onRectChanged: widget.controller.setBounds,
              child: ClipRRect(
                borderRadius: widget.config.borderRadius,
                child: _buildInAppSurface(context, state),
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

  Widget _buildInAppSurface(BuildContext context, UniversalPipState state) {
    if (kIsWeb) {
      final webBuilder = widget.webInAppBuilder;
      if (webBuilder != null) {
        return webBuilder(context, state);
      }
    }
    return widget.inAppBuilder(context, state);
  }

  Widget _buildWebDocumentSurfaceOverlay(
    BuildContext context,
    UniversalPipState state,
  ) {
    final surface = _buildWebDocumentSurface(context, state);
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

  Widget _buildWebDocumentSurface(
    BuildContext context,
    UniversalPipState state,
  ) {
    final builder = widget.webInAppBuilder ?? widget.inAppBuilder;
    return builder(context, state);
  }

  bool _shouldShowSystemSurface(UniversalPipState state) {
    if (kIsWeb) return false;
    if (state.isTransitioning) return true;
    return state.isSystemPipActive &&
        defaultTargetPlatform == TargetPlatform.android;
  }

  bool _shouldShowWebDocumentSurface(UniversalPipState state) {
    return kIsWeb &&
        widget.config.enableWebDocumentPip &&
        state.isTransitioning;
  }

  bool _shouldUseBoundedSystemSurface(UniversalPipState state) {
    return state.isTransitioning;
  }

  void _handleControllerChanged() {
    unawaited(_prepareSystemPip());
    _renderWebDocumentPip();
    _syncFrameworkHandlesBack();
    if (mounted) setState(() {});
  }

  void _renderWebDocumentPip() {
    if (!kIsWeb ||
        !widget.controller.state.isSystemPipActive ||
        widget.webDocumentPipDomBuilder == null) {
      _lastWebDocumentPipWindow = null;
      return;
    }

    final pipWindow = widget.controller.systemPipWindow;
    if (pipWindow == null || identical(pipWindow, _lastWebDocumentPipWindow)) {
      return;
    }

    _lastWebDocumentPipWindow = pipWindow;
    try {
      widget.webDocumentPipDomBuilder!(pipWindow, widget.controller.state);
    } catch (_) {}
  }

  Future<void> _prepareSystemPip() async {
    if (_isPreparingSystemPip) {
      _hasPendingSystemPipPreparation = true;
      return;
    }
    final pipEnabled = kIsWeb
        ? widget.config.enableWebDocumentPip
        : widget.config.enableSystemPip;
    if (!pipEnabled) return;
    if (!widget.controller.state.isVisible) return;

    _isPreparingSystemPip = true;
    try {
      do {
        _hasPendingSystemPipPreparation = false;
        await widget.controller.prepareSystemPip(
          aspectRatio: widget.config.aspectRatio,
          androidSeamlessResize: widget.config.androidSeamlessResize,
          androidAutoEnterOnUserLeave:
              widget.config.androidAutoEnterOnUserLeave,
        );
      } while (_hasPendingSystemPipPreparation);
    } finally {
      _isPreparingSystemPip = false;
    }
  }
}
