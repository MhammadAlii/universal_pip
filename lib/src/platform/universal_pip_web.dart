import 'dart:async';
import 'dart:ui';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../models/native_pip_content.dart';
import 'universal_pip_platform.dart';

class UniversalPipWeb extends UniversalPipPlatform {
  UniversalPipWeb();

  static void registerWith(Registrar registrar) {
    UniversalPipPlatform.instance = UniversalPipWeb();
  }

  @override
  Future<bool> isSystemPipSupported() async => false;

  @override
  Future<String?> getLastSystemPipError() async =>
      'System PiP is not available for this web implementation.';

  @override
  Future<void> configureSystemPip({
    required bool enabled,
    double? aspectRatio,
    bool? androidSeamlessResize,
    bool? androidAutoEnterOnUserLeave,
  }) async {}

  @override
  Future<void> setNativeContent(NativePipContent? content) async {}

  @override
  Future<bool> enterSystemPip() async => false;

  @override
  Future<bool> exitSystemPip() async => false;

  @override
  Future<void> updateSourceRectHint(Rect? rect) async {}

  @override
  Stream<bool> get systemPipModeStream => const Stream<bool>.empty();
}
