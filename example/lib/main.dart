import 'package:flutter/material.dart';
import 'package:universal_pip/universal_pip.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final pipController = UniversalPipController();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static final NativePipContent _callContent = NativePipContent.videoCall(
    participants: const [
      PipParticipant(
        id: 'remote',
        displayName: 'Remote User',
        isLocal: false,
        isCameraEnabled: true,
      ),
      PipParticipant(
        id: 'local',
        displayName: 'You',
        isLocal: true,
        isCameraEnabled: false,
      ),
    ],
  );

  static final NativePipContent _playerContent = NativePipContent.videoPlayer(
    iosVideoUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    posterUrl:
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
    title: 'Big Buck Bunny',
    subtitle: 'iOS native PiP sample',
  );

  @override
  void dispose() {
    pipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      builder: (context, child) {
        return UniversalPip(
          controller: pipController,
          config: const UniversalPipConfig(
            aspectRatio: 9 / 16,
            enableSystemPip: true,
            enableWebDocumentPip: true,
            initialBounds: Rect.fromLTWH(220, 520, 144, 256),
          ),
          inAppBuilder: (context, state) =>
              _PipBubble(content: state.content ?? _callContent),
          webInAppBuilder: (context, state) =>
              _PipBubble(content: state.content ?? _callContent),
          nativeSurfaceBuilder: (context, state, content) =>
              _PipSurface(content: content),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _ExampleHome(
        pipController: pipController,
        callContent: _callContent,
        playerContent: _playerContent,
      ),
    );
  }
}

class _ExampleHome extends StatelessWidget {
  const _ExampleHome({
    required this.pipController,
    required this.callContent,
    required this.playerContent,
  });

  final UniversalPipController pipController;
  final NativePipContent callContent;
  final NativePipContent playerContent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Universal PiP')),
      body: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: () {
                pipController.showForeground(content: callContent);
              },
              child: const Text('Start full call'),
            ),
            FilledButton(
              onPressed: () {
                pipController.minimizeToAppPip(content: callContent);
              },
              child: const Text('Collapse to PiP'),
            ),
            FilledButton(
              onPressed: () {
                pipController.minimizeToAppPip(content: playerContent);
              },
              child: const Text('Show player PiP'),
            ),
            FilledButton(
              onPressed: () async {
                pipController.minimizeToAppPip(content: playerContent);
                final entered = await pipController.enterSystemPip(
                  aspectRatio: 16 / 9,
                );
                final error = entered
                    ? null
                    : await pipController.lastSystemPipError;
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      entered
                          ? 'Native player PiP requested'
                          : error ?? 'Native player PiP is not available here',
                    ),
                  ),
                );
              },
              child: const Text('Enter native player PiP'),
            ),
            OutlinedButton(
              onPressed: () => pipController.hide(),
              child: const Text('Hide'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipBubble extends StatelessWidget {
  const _PipBubble({required this.content});

  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF14181E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.36),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: _PipSurface(content: content),
      ),
    );
  }
}

class _PipSurface extends StatelessWidget {
  const _PipSurface({required this.content});

  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    if (content.type == NativePipContentType.videoPlayer) {
      return _PlayerPipSurface(content: content);
    }

    final participants = content.participants;
    final remote = participants.firstWhere(
      (participant) => !participant.isLocal,
      orElse: () => participants.first,
    );
    final local = participants
        .where((participant) => participant.isLocal)
        .cast<PipParticipant?>()
        .firstOrNull;

    return Stack(
      fit: StackFit.expand,
      children: [
        _ParticipantBackdrop(participant: remote),
        if (local != null)
          const PositionedDirectional(
            end: 10,
            bottom: 10,
            width: 46,
            height: 64,
            child: _LocalPreview(),
          ),
      ],
    );
  }
}

class _PlayerPipSurface extends StatelessWidget {
  const _PlayerPipSurface({required this.content});

  final NativePipContent content;

  @override
  Widget build(BuildContext context) {
    final posterUrl = content.posterUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrl != null)
          Image.network(
            posterUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: Color(0xFF151A20)),
          )
        else
          const ColoredBox(color: Color(0xFF151A20)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.62),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        PositionedDirectional(
          start: 14,
          end: 14,
          bottom: 14,
          child: Text(
            content.title ?? 'Video',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ParticipantBackdrop extends StatelessWidget {
  const _ParticipantBackdrop({required this.participant});

  final PipParticipant participant;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF26313D), Color(0xFF151A20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF384655),
              child: Text(
                _lettersFromName(participant.displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                participant.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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

class _LocalPreview extends StatelessWidget {
  const _LocalPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101318),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
      ),
      child: const Center(
        child: Text(
          'Y',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
