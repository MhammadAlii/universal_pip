import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:universal_pip/universal_pip.dart';
import 'package:universal_pip/src/platform/method_channel_universal_pip.dart';
import 'package:universal_pip/src/platform/universal_pip_platform.dart';

class MockUniversalPipPlatform
    with MockPlatformInterfaceMixin
    implements UniversalPipPlatform {
  final pipModeController = StreamController<bool>.broadcast();
  Rect? lastSourceRectHint;
  bool enabled = false;
  double? aspectRatio;
  bool? androidSeamlessResize;
  bool? androidAutoEnterOnUserLeave;
  bool enterResult = true;
  bool supported = true;
  String? lastError;
  VoidCallback? onEnterSystemPip;

  @override
  Future<void> configureSystemPip({
    required bool enabled,
    double? aspectRatio,
    bool? androidSeamlessResize,
    bool? androidAutoEnterOnUserLeave,
  }) async {
    this.enabled = enabled;
    this.aspectRatio = aspectRatio;
    this.androidSeamlessResize = androidSeamlessResize;
    this.androidAutoEnterOnUserLeave = androidAutoEnterOnUserLeave;
  }

  @override
  Future<void> setNativeContent(NativePipContent? content) async {}

  @override
  Future<bool> enterSystemPip() async {
    onEnterSystemPip?.call();
    return enterResult;
  }

  @override
  Future<bool> exitSystemPip() async => true;

  @override
  Future<bool> isSystemPipSupported() async => supported;

  @override
  Future<String?> getLastSystemPipError() async => lastError;

  @override
  Stream<bool> get systemPipModeStream => pipModeController.stream;

  @override
  Future<void> updateSourceRectHint(Rect? rect) async {
    lastSourceRectHint = rect;
  }
}

void main() {
  test('$MethodChannelUniversalPip is the default instance', () {
    expect(
      UniversalPipPlatform.instance,
      isInstanceOf<MethodChannelUniversalPip>(),
    );
  });

  test('controller enters system PiP with configured aspect ratio', () async {
    final platform = MockUniversalPipPlatform();
    final controller = UniversalPipController(platform: platform);

    controller.show(
      content: NativePipContent.videoPlayer(title: 'Demo'),
      initialBounds: const Rect.fromLTWH(20, 30, 120, 160),
    );

    final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);

    expect(entered, isTrue);
    expect(platform.enabled, isTrue);
    expect(platform.aspectRatio, 16 / 9);
    expect(platform.androidSeamlessResize, isTrue);
    expect(platform.androidAutoEnterOnUserLeave, isTrue);
    expect(platform.lastSourceRectHint, const Rect.fromLTWH(20, 30, 120, 160));
    expect(controller.state.mode, UniversalPipMode.system);

    await controller.disposeLater();
  });

  test(
    'controller pre-renders system surface during default native handoff',
    () async {
      final platform = MockUniversalPipPlatform();
      final controller = UniversalPipController(platform: platform);
      controller.minimizeToAppPip(content: NativePipContent.videoPlayer());

      platform.onEnterSystemPip = () {
        expect(controller.state.mode, UniversalPipMode.system);
        expect(controller.state.isTransitioning, isTrue);
      };

      final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);

      expect(entered, isTrue);
      expect(controller.state.mode, UniversalPipMode.system);

      await controller.disposeLater();
    },
  );

  test(
    'controller can skip pre-rendering system surface before native handoff',
    () async {
      final platform = MockUniversalPipPlatform();
      final controller = UniversalPipController(platform: platform);
      controller.minimizeToAppPip(content: NativePipContent.videoPlayer());

      platform.onEnterSystemPip = () {
        expect(controller.state.mode, UniversalPipMode.inApp);
        expect(controller.state.isTransitioning, isFalse);
      };

      final entered = await controller.enterSystemPip(
        aspectRatio: 16 / 9,
        preRenderSystemSurface: false,
      );

      expect(entered, isTrue);
      expect(controller.state.mode, UniversalPipMode.system);
      expect(controller.state.isTransitioning, isFalse);

      await controller.disposeLater();
    },
  );

  test(
    'system PiP start event keeps transition active until enter completes',
    () async {
      final platform = MockUniversalPipPlatform();
      final controller = UniversalPipController(platform: platform);
      controller.minimizeToAppPip(content: NativePipContent.videoPlayer());

      platform.onEnterSystemPip = () {
        platform.pipModeController.add(true);
      };

      final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);

      expect(entered, isTrue);
      expect(controller.state.mode, UniversalPipMode.system);
      expect(controller.state.isSystemPipActive, isTrue);
      expect(controller.state.isTransitioning, isFalse);

      await controller.disposeLater();
    },
  );

  test(
    'system PiP stop event is ignored while enter request is in flight',
    () async {
      final platform = MockUniversalPipPlatform();
      final controller = UniversalPipController(platform: platform);
      controller.minimizeToAppPip(content: NativePipContent.videoPlayer());

      platform.onEnterSystemPip = () {
        platform.pipModeController.add(false);
      };

      final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);

      expect(entered, isTrue);
      expect(controller.state.mode, UniversalPipMode.system);
      expect(controller.state.isSystemPipActive, isTrue);

      await controller.disposeLater();
    },
  );

  test('system PiP event restores in-app mode when PiP closes', () async {
    final platform = MockUniversalPipPlatform();
    final controller = UniversalPipController(platform: platform);
    controller.show(content: NativePipContent.videoPlayer(title: 'Demo'));

    platform.pipModeController.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isSystemPipActive, isTrue);

    platform.pipModeController.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.mode, UniversalPipMode.inApp);
    expect(controller.state.isSystemPipActive, isFalse);

    await controller.disposeLater();
  });

  test(
    'system PiP restores foreground mode when entered from foreground',
    () async {
      final platform = MockUniversalPipPlatform();
      final controller = UniversalPipController(platform: platform);
      controller.showForeground(
        content: NativePipContent.videoPlayer(title: 'Demo'),
      );

      final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);
      expect(entered, isTrue);
      expect(controller.state.mode, UniversalPipMode.system);
      expect(platform.lastSourceRectHint, isNull);

      platform.pipModeController.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.mode, UniversalPipMode.foreground);

      await controller.disposeLater();
    },
  );

  test('system PiP restores in-app mode when entered from bubble', () async {
    final platform = MockUniversalPipPlatform();
    final controller = UniversalPipController(platform: platform);
    const bounds = Rect.fromLTWH(8, 12, 120, 180);
    controller.minimizeToAppPip(
      content: NativePipContent.videoPlayer(title: 'Demo'),
      initialBounds: bounds,
    );

    final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);
    expect(entered, isTrue);
    expect(controller.state.mode, UniversalPipMode.system);
    expect(platform.lastSourceRectHint, bounds);

    platform.pipModeController.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.mode, UniversalPipMode.inApp);

    await controller.disposeLater();
  });

  test('unsupported platform does not switch to system mode', () async {
    final platform = MockUniversalPipPlatform()..supported = false;
    final controller = UniversalPipController(platform: platform);
    controller.showForeground(
      content: NativePipContent.videoPlayer(title: 'Demo'),
    );

    final entered = await controller.enterSystemPip(aspectRatio: 16 / 9);
    expect(entered, isFalse);
    expect(controller.state.mode, UniversalPipMode.foreground);
    expect(platform.enabled, isFalse);

    await controller.disposeLater();
  });
}

extension on UniversalPipController {
  Future<void> disposeLater() async {
    dispose();
    await Future<void>.delayed(Duration.zero);
  }
}
