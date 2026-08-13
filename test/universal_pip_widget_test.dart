import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_pip/universal_pip.dart';
import 'package:universal_pip/src/widgets/native_pip_content_surface.dart';

void main() {
  testWidgets('non-web in-app PiP uses the platform-neutral builder', (
    tester,
  ) async {
    final controller = UniversalPipController();
    controller.show(
      content: NativePipContent.videoPlayer(title: 'Demo'),
      initialBounds: const Rect.fromLTWH(16, 16, 120, 120),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UniversalPip(
          controller: controller,
          inAppBuilder: (context, state) => const Text('in-app'),
          webInAppBuilder: (context, state) => const Text('web in-app'),
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(find.text('in-app'), findsOneWidget);
    expect(find.text('web in-app'), findsNothing);

    controller.dispose();
  });

  testWidgets('video-call avatar uses configured fallback text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativePipContentSurface(
          content: NativePipContent.videoCall(
            participants: const [
              PipParticipant(
                id: 'remote',
                displayName: 'Remote User',
                avatarFallbackText: 'Guest',
                isCameraEnabled: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Guest'), findsOneWidget);
  });
}
