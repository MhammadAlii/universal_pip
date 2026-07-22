import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import '../models/native_pip_content.dart';
import 'universal_pip_platform.dart';

class UniversalPipWeb extends UniversalPipPlatform {
  UniversalPipWeb();

  final StreamController<bool> _pipModeController =
      StreamController<bool>.broadcast();
  double? _aspectRatio;
  Rect? _sourceRectHint;
  web.Window? _pipWindow;
  String? _lastError;
  Future<void> Function()? _webAutoEnterHandler;

  static void registerWith(Registrar registrar) {
    UniversalPipPlatform.instance = UniversalPipWeb();
  }

  @override
  Future<bool> isSystemPipSupported() async {
    final isSupported = web.window
        .hasProperty('documentPictureInPicture'.toJS)
        .toDart;
    if (!isSupported) {
      _lastError =
          'Document Picture-in-Picture is not available in this browser.';
    }
    return isSupported;
  }

  @override
  Future<String?> getLastSystemPipError() async => _lastError;

  @override
  Future<void> configureSystemPip({
    required bool enabled,
    double? aspectRatio,
    bool? androidSeamlessResize,
    bool? androidAutoEnterOnUserLeave,
  }) async {
    _aspectRatio = aspectRatio;
    if (!enabled) {
      await exitSystemPip();
    }
  }

  @override
  Future<void> setNativeContent(NativePipContent? content) async {}

  @override
  Future<bool> enterSystemPip() async {
    final isSupported = web.window
        .hasProperty('documentPictureInPicture'.toJS)
        .toDart;
    if (!isSupported) {
      _lastError =
          'Document Picture-in-Picture is not available in this browser.';
      return false;
    }

    final existingWindow = _currentDocumentPipWindow;
    if (existingWindow != null) {
      _pipWindow = existingWindow;
      _emitPipMode(true);
      return true;
    }

    try {
      final size = _documentPipSize();
      final options =
          <String, Object?>{
                'width': size.width.round(),
                'height': size.height.round(),
                'preferInitialWindowPlacement': true,
              }.jsify()!
              as JSObject;
      final documentPip =
          web.window.getProperty('documentPictureInPicture'.toJS)! as JSObject;
      final promise = documentPip.callMethod<JSPromise<web.Window>>(
        'requestWindow'.toJS,
        options,
      );
      final pipWindow = await promise.toDart.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
          'Document Picture-in-Picture did not open. It must be requested from a direct user gesture.',
        ),
      );
      _pipWindow = pipWindow;
      _renderDocumentPipHost(pipWindow);
      pipWindow.addEventListener('pagehide', _handlePipWindowClosed.toJS);
      _lastError = null;
      _emitPipMode(true);
      return true;
    } catch (error) {
      _lastError = _friendlyDocumentPipError(error);
      _emitPipMode(false);
      return false;
    }
  }

  @override
  Future<bool> exitSystemPip() async {
    final pipWindow = _pipWindow ?? _currentDocumentPipWindow;
    if (pipWindow == null) return false;

    try {
      pipWindow.close();
    } catch (_) {
      // The browser may already be closing the PiP window.
    } finally {
      _pipWindow = null;
      _emitPipMode(false);
    }
    return true;
  }

  @override
  Future<void> updateSourceRectHint(Rect? rect) async {
    _sourceRectHint = rect;
  }

  @override
  Stream<bool> get systemPipModeStream => _pipModeController.stream;

  @override
  Object? get systemPipWindow => _pipWindow ?? _currentDocumentPipWindow;

  @override
  void setWebAutoEnterHandler(Future<void> Function()? handler) {
    _webAutoEnterHandler = handler;
    final mediaSession = web.window.navigator.getProperty('mediaSession'.toJS);
    if (mediaSession == null || !mediaSession.isA<JSObject>()) return;

    final actionHandler = handler == null
        ? null
        : ((JSAny? _) {
            unawaited(_webAutoEnterHandler?.call());
          }).toJS;
    try {
      (mediaSession as JSObject).callMethod<JSAny?>(
        'setActionHandler'.toJS,
        <JSAny?>['enterpictureinpicture'.toJS, actionHandler].toJS,
      );
    } catch (_) {
      // The Media Session PiP action is unavailable in older browsers.
    }
  }

  web.Window? get _currentDocumentPipWindow {
    if (!web.window.hasProperty('documentPictureInPicture'.toJS).toDart) {
      return null;
    }
    final documentPip = web.window.getProperty('documentPictureInPicture'.toJS);
    if (documentPip == null) return null;
    return (documentPip as JSObject).getProperty('window'.toJS) as web.Window?;
  }

  Size _documentPipSize() {
    final hintedSize = _sourceRectHint?.size;
    if (hintedSize != null &&
        hintedSize.width.isFinite &&
        hintedSize.height.isFinite &&
        hintedSize.width > 0 &&
        hintedSize.height > 0) {
      return hintedSize;
    }

    final aspectRatio = _aspectRatio;
    if (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0) {
      const height = 256.0;
      return Size(height * aspectRatio, height);
    }

    return const Size(360, 240);
  }

  void _renderDocumentPipHost(web.Window pipWindow) {
    final pipDocument = pipWindow.document;
    pipDocument.title = 'Universal PiP';
    final body = pipDocument.body;
    if (body == null) return;

    body.innerHTML =
        '''
<style>
  html, body {
    width: 100%;
    height: 100%;
    margin: 0;
    overflow: hidden;
    background: #111418;
    color: white;
    font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }
  .universal-pip-document {
    width: 100%;
    height: 100%;
    display: grid;
    place-items: center;
    box-sizing: border-box;
    padding: 16px;
    text-align: center;
    background: linear-gradient(145deg, #202833, #101318);
  }
  .universal-pip-document strong {
    display: block;
    font-size: 16px;
    line-height: 1.2;
  }
  .universal-pip-document span {
    display: block;
    margin-top: 6px;
    color: rgba(255, 255, 255, 0.68);
    font-size: 12px;
    line-height: 1.35;
  }
</style>
<div class="universal-pip-document">
  <div>
    <strong>Universal PiP</strong>
    <span>Document Picture-in-Picture is active.</span>
  </div>
</div>
'''
            .toJS;
  }

  void _handlePipWindowClosed(web.Event event) {
    _pipWindow = null;
    _emitPipMode(false);
  }

  void _emitPipMode(bool isActive) {
    if (!_pipModeController.isClosed) {
      _pipModeController.add(isActive);
    }
  }

  String _friendlyDocumentPipError(Object error) {
    final message = error.toString();
    if (message.contains('NotAllowedError')) {
      return 'Document Picture-in-Picture must be opened from a user gesture.';
    }
    if (message.contains('NotSupportedError')) {
      return 'Document Picture-in-Picture is disabled or not supported by this browser.';
    }
    if (message.contains('RangeError')) {
      return 'Document Picture-in-Picture rejected the requested window size.';
    }
    if (message.contains('TimeoutException')) {
      return 'Document Picture-in-Picture did not open. Use a direct user gesture such as a button tap.';
    }
    return 'Could not enter Document Picture-in-Picture: $message';
  }
}
