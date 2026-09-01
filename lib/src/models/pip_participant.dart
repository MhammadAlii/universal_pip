import 'package:flutter/widgets.dart';

class PipParticipant {
  const PipParticipant({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.avatarAuthToken,
    this.avatarFallbackUrl,
    this.avatarFallbackText,
    this.nativeVideoTrackId,
    this.renderer,
    this.videoBuilder,
    this.isLocal = false,
    this.isMuted = false,
    this.isCameraEnabled = true,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;

  /// Bearer token sent with [avatarUrl] and [avatarFallbackUrl].
  ///
  /// Profile endpoints are often authenticated, so the URL alone is not
  /// fetchable. Supplied by the host app, used only as an `Authorization`
  /// header on the avatar request, and never persisted.
  final String? avatarAuthToken;

  /// Image shown if [avatarUrl] is absent or cannot be loaded.
  final String? avatarFallbackUrl;

  /// Text shown if neither [avatarUrl] nor [avatarFallbackUrl] can be loaded.
  ///
  /// Defaults to initials derived from [displayName].
  final String? avatarFallbackText;

  /// Native WebRTC track identifier used by the iOS video-call PiP bridge.
  ///
  /// The [renderer] itself is a Dart object and cannot cross a method channel.
  /// iOS resolves this identifier to the live native `RTCVideoTrack` instead.
  final String? nativeVideoTrackId;

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
      isCameraEnabled &&
      (nativeVideoTrackId != null || renderer != null || videoBuilder != null);
}
