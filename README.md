# universal_pip

`universal_pip` is a Flutter Picture-in-Picture wrapper for apps that need one
controller for:

- foreground PiP content registration
- draggable in-app PiP
- Android system PiP
- iOS native PiP content handoff
- browser-tab in-app PiP
- browser Document Picture-in-Picture on supported web targets

The package separates **mode** from **content**:

- Mode decides where PiP is: hidden, foreground, in-app, or system.
- Content describes what native/system PiP should render: video player data or
  video-call participants.

Flutter in-app PiP is built from your `inAppBuilder`. Native/system PiP uses
`NativePipContent`.

## Modes

The controller state uses `UniversalPipMode`:

```dart
enum UniversalPipMode { hidden, foreground, inApp, system }
```

- `hidden`: PiP is closed.
- `foreground`: the full player/call screen is visible. No in-app bubble is
  shown, but content is kept ready for native/system PiP.
- `inApp`: a draggable Flutter PiP bubble is shown inside the app.
- `system`: native OS PiP or browser Document PiP is active or entering.

## Install at the app root

Mount `UniversalPip` once around the real app/router root:

```dart
final pipController = UniversalPipController();

UniversalPip(
  controller: pipController,
  config: const UniversalPipConfig(
    aspectRatio: 9 / 16,
    enableSystemPip: true,
    enableWebDocumentPip: true,
    autoEnterSystemPip: false,
    initialSize: Size(144, 256),
    minSize: Size(104, 132),
    maxSize: Size(180, 320),
    edgePadding: 16,
  ),
  inAppBuilder: (context, state) => MyInAppPipBubble(state: state),
  nativeSurfaceBuilder: (context, state, content) {
    return MySystemPipTransitionSurface(content: content);
  },
  webDocumentPipDomBuilder: (pipWindow, state) {
    renderDocumentPipDom(pipWindow, state);
  },
  child: const AppRouter(),
);
```

Do not mount the package inside individual routes. Routers can keep multiple
routes mounted, which can create duplicated overlays and duplicated video
surfaces.

## Controller API

### Foreground

Use foreground mode when the full player/call screen is visible:

```dart
pipController.showForeground(content: content);
```

This does not show a floating bubble. It stores fresh native content and marks
the restore target as `foreground`, so if native/system PiP starts from the full
screen, returning from system PiP restores foreground.

### In-App PiP

Use in-app mode when the user minimizes the player/call inside your app:

```dart
pipController.minimizeToAppPip(
  content: content,
  initialBounds: previousBubbleRect,
);
```

`show(...)` is the underlying in-app method. `minimizeToAppPip(...)` is an alias
with call/player-oriented naming.

### Content Updates

Use `setNativeContent(...)` when the call/player content changes but the current
mode should not change:

```dart
pipController.setNativeContent(content);
```

This is useful while native/system PiP is active or transitioning.

### Bounds

The draggable in-app overlay reports its latest rect back into the controller.
The controller sends that rect to Android as `sourceRectHint`:

```dart
pipController.setBounds(rect);
```

When responsive size config changes, the in-app overlay uses the current
`UniversalPipConfig.initialSize` for size. Saved bounds are reused only for
position when their size still matches the current config size.

### System PiP

Enter system PiP explicitly:

```dart
await pipController.enterSystemPip(aspectRatio: 9 / 16);
```

Or configure lifecycle auto-entry:

```dart
UniversalPipConfig(autoEnterSystemPip: true)
```

When system PiP exits, the controller restores the saved target mode:

- entered from `showForeground(...)` -> restores `foreground`
- entered from `minimizeToAppPip(...)` -> restores `inApp`
- if `showForeground(...)` or `minimizeToAppPip(...)` is called while system PiP
  is active, the controller updates the restore target without flashing an
  intermediate Flutter mode

### Hide

End PiP from any UI-aware call/player controller:

```dart
await pipController.hide();
```

`hide()` clears content, disables native PiP configuration, and exits system PiP
if needed.

## Builders

### `inAppBuilder`

Builds the draggable Flutter bubble used inside the app.

### `webInAppBuilder`

Customizes the draggable PiP bubble shown inside the browser
tab. If omitted, the package uses `inAppBuilder`.

### `webDocumentPipDomBuilder`

Renders real DOM content into the browser's separate Document PiP window. Use
this for actual web document PiP content because a separate browser document
cannot automatically host a Flutter widget tree.

### `nativeSurfaceBuilder`

Builds the Flutter preview surface used during native/system PiP handoff. On
Android it can also provide the full Activity surface while system PiP is active.
If omitted, `NativePipContentSurface` renders a default surface from
`NativePipContent`.

## Video Player Content

```dart
final content = NativePipContent.videoPlayer(
  playerRenderer: playerRenderer,
  playerBuilder: (_) => MyPlayerView(renderer: playerRenderer),
  iosVideoUrl: video.streamUrl,
  posterUrl: video.thumbnailUrl,
  title: video.title,
);

pipController.showForeground(content: content);
pipController.minimizeToAppPip(content: content);
```

## Video Call Content

Use one participant list for both 1:1 and group calls:

```dart
final content = NativePipContent.videoCall(
  backgroundColor: const Color(0xFF14181E),
  fallbackBackgroundColor: const Color(0xFF14181E),
  participants: [
    PipParticipant(
      id: 'remote-${remote.id}',
      displayName: remote.name,
      avatarUrl: remote.avatarUrl,
      nativeVideoTrackId: remoteVideoTrackId,
      renderer: remoteRenderer,
      videoBuilder: (_) => RTCVideoView(remoteRenderer),
      isCameraEnabled: remote.isCameraEnabled,
      isMuted: remote.isMuted,
    ),
    PipParticipant(
      id: 'local-${me.id}',
      displayName: me.name,
      avatarUrl: me.avatarUrl,
      nativeVideoTrackId: localVideoTrackId,
      renderer: localRenderer,
      videoBuilder: (_) => RTCVideoView(localRenderer, mirror: true),
      isLocal: true,
      isCameraEnabled: me.isCameraEnabled,
      isMuted: me.isMuted,
    ),
  ],
);
```

Recommended call flow:

1. Full call screen opens: `showForeground(content: callContent)`.
2. Call state changes: `setNativeContent(callContent)` if native/system PiP is
   active, otherwise `showForeground(...)` or `minimizeToAppPip(...)` according
   to your app display mode.
3. User minimizes the call: `minimizeToAppPip(content: callContent)`.
4. User enters system PiP: `enterSystemPip(...)`, or lifecycle auto-entry.
5. User returns from system PiP: package restores the saved target mode.
6. Call ends: `hide()`.

## Android Setup

The host activity must opt in to PiP:

```xml
<activity
    android:name=".MainActivity"
    android:resizeableActivity="true"
    android:supportsPictureInPicture="true"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode">
</activity>
```

For stable native PiP enter/exit events, extend `UniversalPipActivity`:

```kotlin
package com.example.app

import com.mo_dev.universal_pip.UniversalPipActivity

class MainActivity : UniversalPipActivity()
```

Android system PiP captures the Flutter Activity surface. The package prepares
native content, updates `sourceRectHint`, optionally pre-renders a transition
surface, then asks Android System UI to enter PiP.

## iOS Setup

iOS cannot put arbitrary Flutter widgets into native PiP. Native iOS PiP must
use AVKit-backed content, such as player content or native video-call surfaces.

For host apps that use iOS native PiP, enable the iOS background audio/PiP
capability:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Do not add `voip` unless your app uses PushKit/VoIP behavior that Apple expects.

## Web Setup

Flutter web always supports the in-app draggable bubble. Browser-level PiP is
different:

- normal browser video PiP works only with real HTML `<video>` elements
- Document Picture-in-Picture is browser-specific and needs a separate DOM
  renderer

When supported, `enterSystemPip(...)` opens a browser Document PiP window.
Unsupported browsers, insecure contexts, or calls outside a user gesture return
`false` and expose the reason through `lastSystemPipError`.

## Refactoring Notes

Keep the package UI-agnostic:

- business/call state belongs in the host app
- the package tracks PiP mode, bounds, native content, and restore target
- builders should render surfaces only
- call/player repositories should not call PiP APIs directly
