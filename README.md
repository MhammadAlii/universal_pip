# universal_pip

A Flutter Picture-in-Picture wrapper for apps that need one API for:

- draggable in-app PiP
- Android system PiP using the Flutter activity surface
- web/iOS-safe fallbacks while native support is added incrementally

Android system PiP can capture the Flutter root surface. iOS native PiP cannot
capture arbitrary Flutter widgets; it needs native AVKit video/player surfaces.
For that reason, `nativeContentBuilder` returns data describing the PiP content,
while `inAppBuilder` remains fully custom Flutter UI.

## Android setup

The host app activity must opt in to PiP:

```xml
<activity
    android:name=".MainActivity"
    android:resizeableActivity="true"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode">
</activity>
```

For stable native PiP enter/exit events, make your activity extend
`UniversalPipActivity`:

```kotlin
package com.example.app

import com.mo_dev.universal_pip.UniversalPipActivity

class MainActivity : UniversalPipActivity()
```

## iOS setup

iOS does not let a plugin put arbitrary Flutter widgets into native PiP. Native
iOS PiP must be backed by AVKit content, such as an `AVPlayerLayer` for video
playback or native video-call surfaces for calls.

For now, `universal_pip` is safe on iOS:

- in-app PiP works as normal Flutter UI
- native video-player PiP works when `NativePipContent.videoPlayer` includes
  `iosVideoUrl`
- video-call PiP still returns `false` until native call renderer mapping is
  added

Host apps that will add native iOS video PiP should enable the iOS background
audio/PiP capability. In `ios/Runner/Info.plist` this is:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Do not add `voip` unless your app actually uses PushKit/VoIP behavior that
Apple expects.

## Web setup

Flutter web supports the draggable in-app PiP bubble. Browser-level PiP is not
the same as Android Activity PiP:

- normal browser video PiP works only with real HTML `<video>` elements
- Document Picture-in-Picture is browser-specific and cannot automatically
  render an arbitrary Flutter widget in a separate OS window

For now, `universal_pip` keeps web safe:

- in-app PiP works
- `enterSystemPip(...)` returns `false`
- `enableWebDocumentPip` is reserved for a future explicit web document/HTML
  renderer path

## Video player

```dart
final pipController = UniversalPipController();

UniversalPip(
  controller: pipController,
  config: const UniversalPipConfig(
    aspectRatio: 16 / 9,
    enableSystemPip: true,
    initialBounds: Rect.fromLTWH(220, 520, 160, 90),
  ),
  inAppBuilder: (context, state) {
    return MyMiniPlayer(state: state);
  },
  nativeContentBuilder: (context, state) {
    return NativePipContent.videoPlayer(
      playerRenderer: playerRenderer,
      playerBuilder: (_) => MyPlayerView(renderer: playerRenderer),
      iosVideoUrl: currentVideo.streamUrl,
      posterUrl: currentVideo.thumbnailUrl,
      title: currentVideo.title,
    );
  },
  child: const App(),
);
```

Show, enter system PiP, and hide:

```dart
pipController.minimizeToAppPip(
  content: NativePipContent.videoPlayer(
    playerRenderer: playerRenderer,
    playerBuilder: (_) => MyPlayerView(renderer: playerRenderer),
    iosVideoUrl: currentVideo.streamUrl,
    title: currentVideo.title,
  ),
);

await pipController.enterSystemPip(aspectRatio: 16 / 9);
await pipController.hide();
```

## Video call

Use the same participant model for 1:1 and group calls. A 1:1 call is simply a
participant list with two entries.

```dart
final pipController = UniversalPipController();

UniversalPip(
  controller: pipController,
  config: const UniversalPipConfig(
    aspectRatio: 9 / 16,
    enableSystemPip: true,
    enableWebDocumentPip: false,
    initialBounds: Rect.fromLTWH(220, 500, 144, 256),
  ),
  inAppBuilder: (context, state) {
    return MyCallPipBubble(state: state);
  },
  nativeContentBuilder: (context, state) {
    return NativePipContent.videoCall(
      participants: [
        PipParticipant(
          id: remoteUser.id,
          displayName: remoteUser.name,
          avatarUrl: remoteUser.avatarUrl,
          renderer: remoteRenderer,
          videoBuilder: (_) => RTCVideoView(remoteRenderer),
          isLocal: false,
          isMuted: remoteUser.isMuted,
          isCameraEnabled: remoteUser.isCameraEnabled,
        ),
        PipParticipant(
          id: currentUser.id,
          displayName: currentUser.name,
          avatarUrl: currentUser.avatarUrl,
          renderer: localRenderer,
          videoBuilder: (_) => RTCVideoView(localRenderer, mirror: true),
          isLocal: true,
          isMuted: currentUser.isMuted,
          isCameraEnabled: currentUser.isCameraEnabled,
        ),
      ],
    );
  },
  child: const App(),
);
```

Use the controller from your call UI layer:

```dart
final callContent = NativePipContent.videoCall(participants: participants);

// Full call screen is visible. No in-app bubble is shown, but the content is
// ready for Android system PiP if the app is backgrounded.
pipController.showForeground(content: callContent);

// Back button / close icon on the full call screen.
pipController.minimizeToAppPip(content: callContent);

// Hangup from screen, notification, or native callback.
await pipController.hide();
```

When system PiP closes, the plugin restores the previous mode:

- entered from `showForeground(...)` -> restores to `UniversalPipMode.foreground`
- entered from `minimizeToAppPip(...)` -> restores to `UniversalPipMode.inApp`

## Group call

```dart
NativePipContent.videoCall(
  participants: groupParticipants.map((participant) {
    return PipParticipant(
      id: participant.id,
      displayName: participant.name,
      avatarUrl: participant.avatarUrl,
      renderer: participant.videoRenderer,
      videoBuilder: participant.videoRenderer == null
          ? null
          : (_) => RTCVideoView(participant.videoRenderer),
      isLocal: participant.isMe,
      isMuted: participant.isMuted,
      isCameraEnabled: participant.isCameraEnabled,
    );
  }).toList(),
);
```

If a participant has no active renderer, the default native surface falls back
to `avatarUrl`, then short avatar letters generated from `displayName`.

## Initial position

Use `UniversalPipConfig.initialBounds` to choose where the first in-app PiP
appears. The controller keeps the latest dragged bounds and sends them to
Android as the system PiP `sourceRectHint`, so the OS animation starts from the
same on-screen rectangle.

Android controls the final system PiP window position. The plugin can align the
transition origin with the app bubble, but it cannot force the final OS PiP
corner after Android System UI takes over.

## Android handoff strategy

Android system PiP captures the Flutter `Activity`, not a single Flutter widget.
There are two possible handoff styles:

- Default: draw the native PiP surface inside the current bubble bounds for one
  frame, blur the app behind it, then ask Android to enter system PiP. This keeps
  the handoff tied to the latest `sourceRectHint` without growing the bubble to
  full screen first.
- Set `preRenderSystemSurfaceBeforeSystemPip: false` to keep the existing
  in-app PiP bubble visible until Android System UI takes over.
- On Android 12+, `androidSeamlessResize` defaults to `true` so System UI can
  resize the captured surface with less visual jumping.

```dart
UniversalPip(
  controller: pipController,
  config: const UniversalPipConfig(
    aspectRatio: 9 / 16,
    enableSystemPip: true,
    preRenderSystemSurfaceBeforeSystemPip: true,
    androidSeamlessResize: true,
  ),
  inAppBuilder: (context, state) => MyCallBubble(state: state),
  nativeContentBuilder: (context, state) => state.content,
  child: const App(),
);
```

## WhatsApp-style video call integration

Mount `UniversalPip` exactly once at the true app root, around your router/app:

```dart
UniversalPip(
  controller: pipController,
  config: const UniversalPipConfig(
    aspectRatio: 9 / 16,
    enableSystemPip: true,
  ),
  inAppBuilder: (context, state) => MyCallBubble(state: state),
  nativeContentBuilder: (context, state) => state.content,
  nativeSurfaceBuilder: (context, state, content) {
    return MyFullBleedCallPipSurface(content: content);
  },
  child: const App(),
);
```

Do not mount `UniversalPip`, your app bubble, or your system PiP surface inside
per-route wrappers. A Navigator can keep multiple routes mounted, and duplicated
full-screen overlays will create duplicate video surfaces.

Recommended call flow:

1. When the full call screen opens, call `showForeground(content: callContent)`.
2. When the user presses back/close, call `minimizeToAppPip(content: callContent)`.
3. When the app backgrounds, the plugin sends the current bubble bounds as the
   Android `sourceRectHint` and asks Android to enter system PiP.
4. When the app foregrounds, the plugin restores either foreground mode or the
   in-app bubble based on where system PiP was entered from.
5. When the call ends from any source, call `hide()` from your UI-aware call
   controller/view model. Keep repositories/data sources free of PiP UI state.
