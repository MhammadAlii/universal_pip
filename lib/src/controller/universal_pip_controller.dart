import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../models/native_pip_content.dart';
import '../platform/universal_pip_platform.dart';
import 'universal_pip_state.dart';

class UniversalPipController extends ChangeNotifier {
  UniversalPipController({UniversalPipPlatform? platform})
    : _platform = platform ?? UniversalPipPlatform.instance {
    _pipModeSub = _platform.systemPipModeStream.listen(_handleSystemPipMode);
  }

  final UniversalPipPlatform _platform;
  StreamSubscription<bool>? _pipModeSub;
  UniversalPipState _state = const UniversalPipState.hidden();
  UniversalPipMode _restoreModeAfterSystemPip = UniversalPipMode.inApp;
  bool _isEnteringSystemPip = false;

  UniversalPipState get state => _state;

  Future<bool> get isSystemPipSupported => _platform.isSystemPipSupported();

  Future<String?> get lastSystemPipError => _platform.getLastSystemPipError();

  void showForeground({NativePipContent? content, Rect? sourceRectHint}) {
    _show(
      mode: UniversalPipMode.foreground,
      content: content,
      bounds: sourceRectHint,
    );
  }

  void show({NativePipContent? content, Rect? initialBounds}) {
    _show(
      mode: UniversalPipMode.inApp,
      content: content,
      bounds: initialBounds ?? _state.bounds,
    );
  }

  void minimizeToAppPip({NativePipContent? content, Rect? initialBounds}) {
    show(content: content, initialBounds: initialBounds);
  }

  void setNativeContent(NativePipContent content) {
    if (_state.mode == UniversalPipMode.hidden) {
      _setState(
        UniversalPipState(
          mode: UniversalPipMode.hidden,
          isSystemPipActive: false,
          isTransitioning: false,
          bounds: _state.bounds,
          content: content,
        ),
      );
      return;
    }

    _setState(_state.copyWith(content: content));
  }

  void setBounds(Rect bounds) {
    _setState(_state.copyWith(bounds: bounds));
    unawaited(_platform.updateSourceRectHint(bounds));
  }

  Future<bool> enterSystemPip({
    required double aspectRatio,
    bool preRenderSystemSurface = true,
    bool androidSeamlessResize = true,
    bool androidAutoEnterOnUserLeave = true,
  }) async {
    if (_state.mode == UniversalPipMode.hidden) return false;

    _isEnteringSystemPip = true;

    try {
      await _platform.setNativeContent(_state.content);
      final isSupported = await _platform.isSystemPipSupported();
      if (!isSupported) return false;

      _restoreModeAfterSystemPip = _state.mode == UniversalPipMode.system
          ? _restoreModeAfterSystemPip
          : _state.mode;

      await _platform.configureSystemPip(
        enabled: true,
        aspectRatio: aspectRatio,
        androidSeamlessResize: androidSeamlessResize,
        androidAutoEnterOnUserLeave: androidAutoEnterOnUserLeave,
      );
      await _platform.updateSourceRectHint(_state.bounds);

      if (preRenderSystemSurface) {
        _setSystemTransitionState();
        await _waitForSystemSurfaceFrame();
      }

      final entered = await _platform.enterSystemPip();
      if (entered) {
        _setState(
          _state.copyWith(
            mode: UniversalPipMode.system,
            isSystemPipActive: true,
            isTransitioning: false,
          ),
        );
      } else {
        _setState(
          _state.copyWith(
            mode: _restoreModeAfterSystemPip,
            isSystemPipActive: false,
            isTransitioning: false,
          ),
        );
      }
      return entered;
    } finally {
      _isEnteringSystemPip = false;
    }
  }

  Future<void> prepareSystemPip({
    required double aspectRatio,
    bool androidSeamlessResize = true,
    bool androidAutoEnterOnUserLeave = true,
  }) async {
    if (_state.mode == UniversalPipMode.hidden) return;

    await _platform.setNativeContent(_state.content);
    await _platform.configureSystemPip(
      enabled: true,
      aspectRatio: aspectRatio,
      androidSeamlessResize: androidSeamlessResize,
      androidAutoEnterOnUserLeave: androidAutoEnterOnUserLeave,
    );
    await _platform.updateSourceRectHint(_state.bounds);
  }

  void restoreInAppPip() {
    if (_state.mode == UniversalPipMode.hidden) return;
    _setState(
      _state.copyWith(
        mode: _restoreModeAfterSystemPip,
        isSystemPipActive: false,
        isTransitioning: false,
      ),
    );
  }

  Future<void> exitSystemPip() async {
    await _platform.exitSystemPip();
  }

  Future<void> hide() async {
    final wasSystemPipActive = _state.isSystemPipActive;
    _setState(const UniversalPipState.hidden());
    _restoreModeAfterSystemPip = UniversalPipMode.inApp;
    await _platform.setNativeContent(null);
    await _platform.configureSystemPip(enabled: false);
    if (wasSystemPipActive) {
      await _platform.exitSystemPip();
    }
  }

  @override
  void dispose() {
    _pipModeSub?.cancel();
    super.dispose();
  }

  void _handleSystemPipMode(bool isActive) {
    if (isActive) {
      _setState(
        _state.copyWith(
          mode: UniversalPipMode.system,
          isSystemPipActive: true,
          isTransitioning: _state.isTransitioning,
        ),
      );
      return;
    }

    if (_state.mode == UniversalPipMode.hidden) {
      _setState(
        _state.copyWith(isSystemPipActive: false, isTransitioning: false),
      );
      return;
    }

    if (_isEnteringSystemPip) {
      return;
    }

    _setState(
      _state.copyWith(
        mode: _restoreModeAfterSystemPip,
        isSystemPipActive: false,
        isTransitioning: false,
      ),
    );
  }

  void _setState(UniversalPipState state) {
    _state = state;
    notifyListeners();
  }

  void _show({
    required UniversalPipMode mode,
    NativePipContent? content,
    Rect? bounds,
  }) {
    _setState(
      UniversalPipState(
        mode: mode,
        isSystemPipActive: false,
        isTransitioning: false,
        bounds: bounds,
        content: content ?? _state.content,
      ),
    );
  }

  void _setSystemTransitionState() {
    _setState(
      _state.copyWith(mode: UniversalPipMode.system, isTransitioning: true),
    );
  }

  Future<void> _waitForSystemSurfaceFrame() async {
    try {
      final binding = SchedulerBinding.instance;
      binding.scheduleFrame();
      await binding.endOfFrame;
    } catch (_) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}
