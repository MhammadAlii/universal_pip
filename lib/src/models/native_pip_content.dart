import 'package:flutter/widgets.dart';

import 'pip_participant.dart';

enum NativePipContentType { videoPlayer, videoCall }

class NativePipContent {
  const NativePipContent._({
    required this.type,
    this.playerRenderer,
    this.playerBuilder,
    this.posterUrl,
    this.title,
    this.subtitle,
    this.iosVideoUrl,
    this.participants = const [],
  });

  factory NativePipContent.videoPlayer({
    Object? playerRenderer,
    WidgetBuilder? playerBuilder,
    String? posterUrl,
    String? title,
    String? subtitle,
    String? iosVideoUrl,
  }) {
    return NativePipContent._(
      type: NativePipContentType.videoPlayer,
      playerRenderer: playerRenderer,
      playerBuilder: playerBuilder,
      posterUrl: posterUrl,
      title: title,
      subtitle: subtitle,
      iosVideoUrl: iosVideoUrl,
    );
  }

  factory NativePipContent.videoCall({
    required List<PipParticipant> participants,
  }) {
    return NativePipContent._(
      type: NativePipContentType.videoCall,
      participants: List.unmodifiable(participants),
    );
  }

  final NativePipContentType type;
  final Object? playerRenderer;
  final WidgetBuilder? playerBuilder;
  final String? posterUrl;
  final String? title;
  final String? subtitle;
  final String? iosVideoUrl;
  final List<PipParticipant> participants;
}
