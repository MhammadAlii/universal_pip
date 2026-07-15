import 'dart:async';
import 'dart:ui';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/native_pip_content.dart';
import 'method_channel_universal_pip.dart';

abstract class UniversalPipPlatform extends PlatformInterface {
  UniversalPipPlatform() : super(token: _token);

  static final Object _token = Object();

  static UniversalPipPlatform _instance = MethodChannelUniversalPip();

  static UniversalPipPlatform get instance => _instance;

  static set instance(UniversalPipPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> isSystemPipSupported() {
    throw UnimplementedError('isSystemPipSupported() is not implemented.');
  }

  Future<String?> getLastSystemPipError() {
    throw UnimplementedError('getLastSystemPipError() is not implemented.');
  }

  Future<void> configureSystemPip({
    required bool enabled,
    double? aspectRatio,
    bool? androidSeamlessResize,
    bool? androidAutoEnterOnUserLeave,
  }) {
    throw UnimplementedError('configureSystemPip() is not implemented.');
  }

  Future<void> setNativeContent(NativePipContent? content) {
    throw UnimplementedError('setNativeContent() is not implemented.');
  }

  Future<bool> enterSystemPip() {
    throw UnimplementedError('enterSystemPip() is not implemented.');
  }

  Future<bool> exitSystemPip() {
    throw UnimplementedError('exitSystemPip() is not implemented.');
  }

  Future<void> updateSourceRectHint(Rect? rect) {
    throw UnimplementedError('updateSourceRectHint() is not implemented.');
  }

  Stream<bool> get systemPipModeStream => const Stream<bool>.empty();
}
