import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_pip/universal_pip.dart';

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
}
