import 'package:flutter/widgets.dart';

class PipParticipant {
  const PipParticipant({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.renderer,
    this.videoBuilder,
    this.isLocal = false,
    this.isMuted = false,
    this.isCameraEnabled = true,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;

  /// Platform-specific renderer handle.
  ///
  /// The package keeps this as [Object] so apps can pass their own renderer
  /// type, for example a WebRTC renderer. Native integrations can interpret it
  /// later without forcing a video dependency into this package.
  final Object? renderer;

  /// Flutter surface used by Android system PiP and in-app previews.
  ///
  /// iOS native PiP cannot render arbitrary Flutter widgets; it must use native
  /// video-call/player surfaces.
  final WidgetBuilder? videoBuilder;

  final bool isLocal;
  final bool isMuted;
  final bool isCameraEnabled;

  bool get hasVideo =>
      isCameraEnabled && (renderer != null || videoBuilder != null);
}
