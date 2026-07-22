import 'dart:ui';

import '../models/native_pip_content.dart';

enum UniversalPipMode { hidden, foreground, inApp, system }

// * hidden
// Nothing is shown. PiP is closed.
// * foreground
// The content is active in the app, usually on the full call/player screen. No small bubble is shown, but the controller remembers the content so it can enter native PiP if needed.
// * inApp
// The small draggable Flutter PiP bubble is shown inside the app/browser tab.
// This uses inAppBuilder, or webInAppBuilder on web when provided.
// * system
// The app is entering or already inside native OS PiP. On Android this uses the app Activity surface; on iOS this uses native AVKit content.
// On web this represents browser Document Picture-in-Picture when supported by the web implementation.

class UniversalPipState {
  const UniversalPipState({
    required this.mode,
    required this.isSystemPipActive,
    required this.isTransitioning,
    this.bounds,
    this.content,
  });

  const UniversalPipState.hidden()
    : mode = UniversalPipMode.hidden,
      isSystemPipActive = false,
      isTransitioning = false,
      bounds = null,
      content = null;

  final UniversalPipMode mode;
  final bool isSystemPipActive;
  final bool isTransitioning;
  final Rect? bounds;
  final NativePipContent? content;

  bool get isVisible => mode != UniversalPipMode.hidden;
  bool get isForeground => mode == UniversalPipMode.foreground;
  bool get isInApp => mode == UniversalPipMode.inApp;
  bool get isSystem => mode == UniversalPipMode.system;
  bool get showInAppPip => mode == UniversalPipMode.inApp && !isSystemPipActive;
  bool get showSystemSurface => isTransitioning;

  UniversalPipState copyWith({
    UniversalPipMode? mode,
    bool? isSystemPipActive,
    bool? isTransitioning,
    Rect? bounds,
    NativePipContent? content,
  }) {
    return UniversalPipState(
      mode: mode ?? this.mode,
      isSystemPipActive: isSystemPipActive ?? this.isSystemPipActive,
      isTransitioning: isTransitioning ?? this.isTransitioning,
      bounds: bounds ?? this.bounds,
      content: content ?? this.content,
    );
  }
}
