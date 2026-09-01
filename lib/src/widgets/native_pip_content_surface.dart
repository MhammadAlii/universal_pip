import 'package:flutter/material.dart';

import '../models/native_pip_content.dart';
import '../models/pip_participant.dart';

/// Shows [source], attaching [authToken] when the endpoint requires one.
///
/// Profile URLs are frequently authenticated; without the header the request
/// comes back 401 and the caller only ever sees the fallback.
Widget _sourceImage(
  String source, {
  String? authToken,
  required WidgetBuilder onError,
}) {
  final value = source.trim();
  final token = authToken?.trim();
  final headers = token == null || token.isEmpty
      ? null
      : <String, String>{'Authorization': 'Bearer $token'};

  debugPrint(
    '[PipAvatar] flutter source=$value authorized=${headers != null}',
  );

  return Image.network(
    value,
    fit: BoxFit.cover,
    headers: headers,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (frame == 0) debugPrint('[PipAvatar] flutter loaded source=$value');
      return child;
    },
    errorBuilder: (context, error, stackTrace) {
      debugPrint('[PipAvatar] flutter failed source=$value error=$error');
      return onError(context);
    },
  );
}

class NativePipContentSurface extends StatelessWidget {
  const NativePipContentSurface({required this.content, super.key});

  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: content.videoCallBackgroundColor ?? const Color(0xFF111418),
      child: switch (content.type) {
        NativePipContentType.videoPlayer => _VideoPlayerSurface(
          content: content,
        ),
        NativePipContentType.videoCall => _VideoCallSurface(content: content),
      },
    );
  }
}

class _VideoPlayerSurface extends StatelessWidget {
  const _VideoPlayerSurface({required this.content});

  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    final playerBuilder = content.playerBuilder;
    if (playerBuilder != null) {
      return playerBuilder(context);
    }

    final posterUrl = content.posterUrl;
    if (posterUrl != null && posterUrl.isNotEmpty) {
      return _sourceImage(
        posterUrl,
        onError: (context) =>
            _TextFallback(title: content.title, subtitle: content.subtitle),
      );
    }

    return _TextFallback(title: content.title, subtitle: content.subtitle);
  }
}

class _VideoCallSurface extends StatelessWidget {
  const _VideoCallSurface({required this.content});

  final NativePipContent content;

  List<PipParticipant> get participants => content.participants;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const SizedBox.expand();
    }

    final mainParticipant = _mainParticipant();
    final localParticipant = participants
        .where((participant) => participant.isLocal)
        .cast<PipParticipant?>()
        .firstOrNull;

    return Stack(
      fit: StackFit.expand,
      children: [
        _ParticipantTile(participant: mainParticipant, content: content),
        if (localParticipant != null &&
            localParticipant.id != mainParticipant.id)
          PositionedDirectional(
            end: 12,
            bottom: 12,
            width: 108,
            height: 156,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: _ParticipantTile(
                  participant: localParticipant,
                  content: content,
                ),
              ),
            ),
          ),
      ],
    );
  }

  PipParticipant _mainParticipant() {
    return participants.firstWhere(
      (participant) => !participant.isLocal && participant.hasVideo,
      orElse: () => participants.firstWhere(
        (participant) => !participant.isLocal,
        orElse: () => participants.first,
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, required this.content});

  final PipParticipant participant;
  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    final videoBuilder = participant.videoBuilder;
    if (participant.hasVideo && videoBuilder != null) {
      return videoBuilder(context);
    }

    final avatarUrl = participant.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return _sourceImage(
        avatarUrl,
        authToken: participant.avatarAuthToken,
        onError: (context) =>
            _AvatarFallback(participant: participant, content: content),
      );
    }

    return _AvatarFallback(participant: participant, content: content);
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.participant, required this.content});

  final PipParticipant participant;
  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    final fallbackUrl = participant.avatarFallbackUrl?.trim();
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return _sourceImage(
        fallbackUrl,
        authToken: participant.avatarAuthToken,
        onError: (context) =>
            _AvatarTextFallback(participant: participant, content: content),
      );
    }

    return _AvatarTextFallback(participant: participant, content: content);
  }
}

class _AvatarTextFallback extends StatelessWidget {
  const _AvatarTextFallback({required this.participant, required this.content});

  final PipParticipant participant;
  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    final configuredText = participant.avatarFallbackText?.trim();
    final label = configuredText == null || configuredText.isEmpty
        ? _lettersFromName(participant.displayName)
        : configuredText;

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: content.videoCallFallbackBackgroundColor,
        gradient: content.videoCallFallbackBackgroundColor == null
            ? const LinearGradient(
                colors: [Color(0xFF26313D), Color(0xFF151A20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            alignment: Alignment.center,
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color:
                  content.videoCallProfileBackgroundColor ??
                  Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.84),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _lettersFromName(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}

class _TextFallback extends StatelessWidget {
  const _TextFallback({this.title, this.subtitle});

  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF202833), Color(0xFF101318)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
