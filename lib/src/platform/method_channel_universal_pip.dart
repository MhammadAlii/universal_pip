import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/native_pip_content.dart';
import 'universal_pip_platform.dart';

class MethodChannelUniversalPip extends UniversalPipPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('universal_pip/methods');

  @visibleForTesting
  final eventChannel = const EventChannel('universal_pip/events');

  @override
  Future<bool> isSystemPipSupported() async {
    try {
      return await methodChannel.invokeMethod<bool>('isSystemPipSupported') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String?> getLastSystemPipError() async {
    try {
      return await methodChannel.invokeMethod<String>('getLastSystemPipError');
    } on MissingPluginException {
      return 'Native PiP diagnostic method is missing. Stop the app and rebuild it with flutter clean so the latest iOS plugin code is installed.';
    }
  }

  @override
  Future<void> configureSystemPip({
    required bool enabled,
    double? aspectRatio,
    bool? androidSeamlessResize,
    bool? androidAutoEnterOnUserLeave,
  }) async {
    try {
      final arguments = <String, Object?>{'enabled': enabled};
      if (aspectRatio != null) {
        arguments['aspectRatio'] = aspectRatio;
      }
      if (androidSeamlessResize != null) {
        arguments['androidSeamlessResize'] = androidSeamlessResize;
      }
      if (androidAutoEnterOnUserLeave != null) {
        arguments['androidAutoEnterOnUserLeave'] = androidAutoEnterOnUserLeave;
      }
      await methodChannel.invokeMethod<void>('configureSystemPip', arguments);
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> setNativeContent(NativePipContent? content) async {
    try {
      await methodChannel.invokeMethod<void>(
        'setNativeContent',
        _serializeNativeContent(content),
      );
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<bool> enterSystemPip() async {
    try {
      return await methodChannel.invokeMethod<bool>('enterSystemPip') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> exitSystemPip() async {
    try {
      return await methodChannel.invokeMethod<bool>('exitSystemPip') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> updateSourceRectHint(Rect? rect) async {
    try {
      if (rect == null) {
        await methodChannel.invokeMethod<void>('updateSourceRectHint');
        return;
      }

      final dpr = PlatformDispatcher.instance.views.first.devicePixelRatio;
      await methodChannel.invokeMethod<void>('updateSourceRectHint', {
        'left': (rect.left * dpr).round(),
        'top': (rect.top * dpr).round(),
        'right': (rect.right * dpr).round(),
        'bottom': (rect.bottom * dpr).round(),
      });
    } on MissingPluginException {
      return;
    }
  }

  @override
  Stream<bool> get systemPipModeStream => eventChannel
      .receiveBroadcastStream()
      .map((event) {
        if (event is Map && event['type'] == 'debug') {
          final message = event['message'];
          if (message is String) {
            debugPrint('[UniversalPip][iOS][WebRTC] $message');
          }
        }
        return event;
      })
      .where((event) => event is bool)
      .cast<bool>()
      .handleError((_) {}, test: (error) => error is MissingPluginException);

  Map<String, Object?>? _serializeNativeContent(NativePipContent? content) {
    if (content == null) return null;

    return switch (content.type) {
      NativePipContentType.videoPlayer => <String, Object?>{
        'type': 'videoPlayer',
        'iosVideoUrl': content.iosVideoUrl,
        'title': content.title,
        'subtitle': content.subtitle,
        'posterUrl': content.posterUrl,
      },
      NativePipContentType.videoCall => <String, Object?>{
        'type': 'videoCall',
        'backgroundColor': content.videoCallBackgroundColor?.toARGB32(),
        'fallbackBackgroundColor': content.videoCallFallbackBackgroundColor
            ?.toARGB32(),
        'profileBackgroundColor': content.videoCallProfileBackgroundColor
            ?.toARGB32(),
        'iosPreferredContentSize': _serializeSize(
          content.iosVideoCallPreferredContentSize,
        ),
        'iosLocalPreviewWidthRatio': content.iosVideoCallLocalPreviewWidthRatio,
        'participants': content.participants
            .map(
              (participant) => <String, Object?>{
                'id': participant.id,
                'displayName': participant.displayName,
                'avatarUrl': participant.avatarUrl,
                'nativeVideoTrackId': participant.nativeVideoTrackId,
                'isLocal': participant.isLocal,
                'isMuted': participant.isMuted,
                'isCameraEnabled': participant.isCameraEnabled,
              },
            )
            .toList(),
      },
    };
  }

  Map<String, double>? _serializeSize(Size? size) {
    if (size == null || !size.isFinite || size.isEmpty) return null;

    return {'width': size.width, 'height': size.height};
  }
}
