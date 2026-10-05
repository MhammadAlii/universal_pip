import 'package:flutter/widgets.dart';

class UniversalPipConfig {
  const UniversalPipConfig({
    this.aspectRatio = 16 / 9,
    this.enableSystemPip = true,
    this.enableWebDocumentPip = false,
    this.autoEnterSystemPip = true,
    this.preRenderSystemSurfaceBeforeSystemPip = true,
    this.androidSeamlessResize = true,
    this.androidAutoEnterOnUserLeave = true,
    this.enterSystemPipOnBack = false,
    this.initialBounds,
    this.initialSize = const Size(144, 256),
    this.minSize = const Size(96, 96),
    this.maxSize,
    this.edgePadding = 16,
    this.snapToEdge = true,
    this.animationDuration = const Duration(milliseconds: 220),
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.transitionBlurSigma = 8,
  });

  final double aspectRatio;
  final bool enableSystemPip;
  final bool enableWebDocumentPip;
  final bool autoEnterSystemPip;
  final bool preRenderSystemSurfaceBeforeSystemPip;
  final bool androidSeamlessResize;
  final bool androidAutoEnterOnUserLeave;
  final bool enterSystemPipOnBack;
  final Rect? initialBounds;
  final Size initialSize;
  final Size minSize;
  final Size? maxSize;
  final double edgePadding;
  final bool snapToEdge;
  final Duration animationDuration;
  final BorderRadius borderRadius;
  final double transitionBlurSigma;
}
