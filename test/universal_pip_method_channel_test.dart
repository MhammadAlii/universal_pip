import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_pip/universal_pip.dart';
import 'package:universal_pip/src/platform/method_channel_universal_pip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelUniversalPip();
  const methodChannel = MethodChannel('universal_pip/methods');

  final calls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (methodCall) async {
          calls.add(methodCall);
          return switch (methodCall.method) {
            'isSystemPipSupported' => true,
            'getLastSystemPipError' => 'Not supported here',
            'enterSystemPip' => true,
            'exitSystemPip' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('isSystemPipSupported calls platform channel', () async {
    expect(await platform.isSystemPipSupported(), isTrue);
    expect(calls.single.method, 'isSystemPipSupported');
  });

  test('getLastSystemPipError calls platform channel', () async {
    expect(await platform.getLastSystemPipError(), 'Not supported here');
    expect(calls.single.method, 'getLastSystemPipError');
  });

  test('configureSystemPip sends enabled and aspect ratio', () async {
    await platform.configureSystemPip(
      enabled: true,
      aspectRatio: 16 / 9,
      androidSeamlessResize: true,
      androidAutoEnterOnUserLeave: true,
    );

    expect(calls.single.method, 'configureSystemPip');
    expect(calls.single.arguments, {
      'enabled': true,
      'aspectRatio': 16 / 9,
      'androidSeamlessResize': true,
      'androidAutoEnterOnUserLeave': true,
    });
  });

  test('setNativeContent sends iOS video player URL', () async {
    await platform.setNativeContent(
      NativePipContent.videoPlayer(
        iosVideoUrl: 'https://example.com/video.mp4',
        title: 'Demo',
      ),
    );

    expect(calls.single.method, 'setNativeContent');
    expect(calls.single.arguments, {
      'type': 'videoPlayer',
      'iosVideoUrl': 'https://example.com/video.mp4',
      'title': 'Demo',
      'subtitle': null,
      'posterUrl': null,
    });
  });

  test('setNativeContent sends iOS video call participants', () async {
    await platform.setNativeContent(
      NativePipContent.videoCall(
        participants: const [
          PipParticipant(
            id: 'remote',
            displayName: 'Remote User',
            isLocal: false,
            avatarUrl: 'https://example.com/avatar.png',
            avatarFallbackUrl: 'https://example.com/fallback.png',
            avatarFallbackText: 'Guest',
            isCameraEnabled: true,
          ),
          PipParticipant(
            id: 'local',
            displayName: 'You',
            isLocal: true,
            isMuted: true,
            isCameraEnabled: false,
          ),
        ],
      ),
    );

    expect(calls.single.method, 'setNativeContent');
    expect(calls.single.arguments, {
      'type': 'videoCall',
      'backgroundColor': null,
      'fallbackBackgroundColor': null,
      'profileBackgroundColor': null,
      'iosPreferredContentSize': null,
      'iosLocalPreviewWidthRatio': null,
      'participants': [
        {
          'id': 'remote',
          'displayName': 'Remote User',
          'avatarUrl': 'https://example.com/avatar.png',
          'avatarFallbackUrl': 'https://example.com/fallback.png',
          'avatarFallbackText': 'Guest',
          'nativeVideoTrackId': null,
          'isLocal': false,
          'isMuted': false,
          'isCameraEnabled': true,
        },
        {
          'id': 'local',
          'displayName': 'You',
          'avatarUrl': null,
          'avatarFallbackUrl': null,
          'avatarFallbackText': null,
          'nativeVideoTrackId': null,
          'isLocal': true,
          'isMuted': true,
          'isCameraEnabled': false,
        },
      ],
    });
  });

  test('updateSourceRectHint sends physical rect', () async {
    await platform.updateSourceRectHint(const Rect.fromLTWH(1, 2, 3, 4));

    expect(calls.single.method, 'updateSourceRectHint');
    expect((calls.single.arguments as Map<Object?, Object?>).keys, {
      'left',
      'top',
      'right',
      'bottom',
    });
  });
}
