import Flutter
import AVFoundation
import AVKit
import UIKit

public class UniversalPipPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, AVPictureInPictureControllerDelegate {
  private var eventSink: FlutterEventSink?
  private var pipController: AVPictureInPictureController?
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var playerHostView: UIView?
  private var callSourceView: UIView?
  private var callViewController: UIViewController?
  private var sourceRectHint: CGRect?
  private var activeContentKey: String?
  private var pendingStartResult: FlutterResult?
  private var pendingStartTimeout: Timer?
  private var lastError: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "universal_pip/methods",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "universal_pip/events",
      binaryMessenger: registrar.messenger()
    )
    let instance = UniversalPipPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSystemPipSupported":
      result(isPictureInPictureSupported())
    case "getLastSystemPipError":
      result(lastError)
    case "configureSystemPip":
      result(nil)
    case "setNativeContent":
      setNativeContent(call.arguments)
      result(nil)
    case "updateSourceRectHint":
      updateSourceRectHint(call.arguments)
      result(nil)
    case "enterSystemPip":
      enterPictureInPicture(result: result)
    case "exitSystemPip":
      result(exitPictureInPicture())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    events(false)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func isPictureInPictureSupported() -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      setLastError("iOS AVKit Picture-in-Picture is not supported on this device or runtime.")
      return false
    }
    let hasContent = pipController != nil
    if !hasContent {
      setLastError("iOS PiP is supported, but no native PiP content is prepared.")
    }
    return hasContent
  }

  private func setNativeContent(_ arguments: Any?) {
    guard
      let content = arguments as? [String: Any],
      let type = content["type"] as? String
    else {
      clearNativeContent(resetError: true)
      return
    }

    switch type {
    case "videoPlayer":
      guard
        let urlString = content["iosVideoUrl"] as? String,
        let url = URL(string: urlString)
      else {
        setLastError("iOS native PiP requires NativePipContent.videoPlayer(iosVideoUrl: ...).")
        clearNativeContent(resetError: false)
        return
      }
      preparePlayerContent(url: url)
    case "videoCall":
      let participants = parseParticipants(content["participants"])
      prepareVideoCallContent(participants: participants)
    default:
      setLastError("Unsupported iOS PiP content type: \(type).")
      clearNativeContent(resetError: false)
    }
  }

  private func preparePlayerContent(url: URL) {
    let contentKey = "videoPlayer:\(url.absoluteString)"
    if activeContentKey == contentKey,
       pipController != nil,
       player != nil {
      return
    }

    clearNativeContent(emitInactive: false)

    let nextPlayer = AVPlayer(url: url)
    nextPlayer.isMuted = true
    let nextLayer = AVPlayerLayer(player: nextPlayer)
    nextLayer.videoGravity = .resizeAspect

    guard let hostView = attachPlayerLayer(nextLayer) else {
      setLastError("iOS could not attach the native AVPlayerLayer to the active Flutter view.")
      return
    }

    let nextController = AVPictureInPictureController(playerLayer: nextLayer)
    nextController?.delegate = self
    if #available(iOS 14.2, *) {
      nextController?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    player = nextPlayer
    playerLayer = nextLayer
    playerHostView = hostView
    pipController = nextController
    if nextController == nil {
      setLastError("iOS could not create AVPictureInPictureController for this player layer.")
    } else {
      activeContentKey = contentKey
      lastError = nil
    }
  }

  private func prepareVideoCallContent(participants: [NativePipParticipant]) {
    guard #available(iOS 15.0, *) else {
      setLastError("iOS video-call PiP requires iOS 15.0 or newer.")
      clearNativeContent(resetError: false)
      return
    }

    let contentKey = "videoCall:\(participants.map { $0.cacheKey }.joined(separator: "|"))"
    if activeContentKey == contentKey,
       pipController != nil,
       player == nil {
      return
    }

    clearNativeContent(emitInactive: false)

    guard let sourceView = attachCallSourceView() else {
      setLastError("Cannot attach iOS video-call PiP source view: no active root view.")
      return
    }

    let videoCallController = AVPictureInPictureVideoCallViewController()
    videoCallController.preferredContentSize = CGSize(width: 360, height: 640)
    configureVideoCallView(videoCallController.view, participants: participants)

    let contentSource = AVPictureInPictureController.ContentSource(
      activeVideoCallSourceView: sourceView,
      contentViewController: videoCallController
    )
    let nextController = AVPictureInPictureController(contentSource: contentSource)
    nextController.delegate = self
    if #available(iOS 14.2, *) {
      nextController.canStartPictureInPictureAutomaticallyFromInline = true
    }

    callSourceView = sourceView
    callViewController = videoCallController
    pipController = nextController
    activeContentKey = contentKey
    lastError = nil
  }

  private func attachPlayerLayer(_ layer: AVPlayerLayer) -> UIView? {
    guard let hostView = attachSourceView() else {
      setLastError("Cannot attach iOS PiP player layer: no active root view.")
      return nil
    }

    layer.frame = hostView.bounds
    hostView.layer.addSublayer(layer)
    return hostView
  }

  private func attachCallSourceView() -> UIView? {
    guard let rootView = activeRootView() else {
      return nil
    }

    let sourceView = UIView(frame: sourceRectHint ?? fallbackSourceRect(in: rootView))
    sourceView.isUserInteractionEnabled = false
    sourceView.backgroundColor = .clear
    sourceView.autoresizingMask = []
    rootView.addSubview(sourceView)
    return sourceView
  }

  private func updateSourceRectHint(_ arguments: Any?) {
    guard
      let rect = sourceRect(from: arguments),
      let rootView = activeRootView()
    else {
      sourceRectHint = nil
      callSourceView?.frame = activeRootView().map { fallbackSourceRect(in: $0) } ?? .zero
      return
    }

    let boundedRect = rect.intersection(rootView.bounds)
    sourceRectHint = boundedRect.isNull ? fallbackSourceRect(in: rootView) : boundedRect
    callSourceView?.frame = sourceRectHint ?? fallbackSourceRect(in: rootView)
  }

  private func sourceRect(from arguments: Any?) -> CGRect? {
    guard
      let rect = arguments as? [String: Any],
      let left = number(from: rect["left"]),
      let top = number(from: rect["top"]),
      let right = number(from: rect["right"]),
      let bottom = number(from: rect["bottom"]),
      right > left,
      bottom > top
    else {
      return nil
    }

    let scale = max(UIScreen.main.scale, 1)
    return CGRect(
      x: left / scale,
      y: top / scale,
      width: (right - left) / scale,
      height: (bottom - top) / scale
    )
  }

  private func number(from value: Any?) -> CGFloat? {
    if let value = value as? NSNumber {
      return CGFloat(truncating: value)
    }
    if let value = value as? Double {
      return CGFloat(value)
    }
    if let value = value as? Int {
      return CGFloat(value)
    }
    return nil
  }

  private func fallbackSourceRect(in rootView: UIView) -> CGRect {
    let size = CGSize(width: 2, height: 2)
    return CGRect(
      x: max(rootView.bounds.maxX - size.width, 0),
      y: max(rootView.bounds.maxY - size.height, 0),
      width: size.width,
      height: size.height
    )
  }

  private func attachSourceView() -> UIView? {
    guard let rootView = activeRootView() else {
      return nil
    }

    let size: CGFloat = 2
    let origin = CGPoint(
      x: max(rootView.bounds.width - size, 0),
      y: max(rootView.bounds.height - size, 0)
    )
    let hostView = UIView(frame: CGRect(origin: origin, size: CGSize(width: size, height: size)))
    hostView.isUserInteractionEnabled = false
    hostView.clipsToBounds = true
    hostView.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
    hostView.backgroundColor = .black
    rootView.addSubview(hostView)
    return hostView
  }

  private func parseParticipants(_ value: Any?) -> [NativePipParticipant] {
    guard let participantMaps = value as? [[String: Any]] else {
      return []
    }

    return participantMaps.map { participant in
      NativePipParticipant(
        id: participant["id"] as? String ?? UUID().uuidString,
        displayName: participant["displayName"] as? String ?? "Participant",
        avatarUrl: participant["avatarUrl"] as? String,
        isLocal: participant["isLocal"] as? Bool ?? false,
        isMuted: participant["isMuted"] as? Bool ?? false,
        isCameraEnabled: participant["isCameraEnabled"] as? Bool ?? true
      )
    }
  }

  private func configureVideoCallView(
    _ view: UIView,
    participants: [NativePipParticipant]
  ) {
    view.subviews.forEach { $0.removeFromSuperview() }
    view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1.0)

    let remote = participants.first { !$0.isLocal } ?? participants.first
    let local = participants.first { $0.isLocal }
    let callView = NativePipVideoCallView(
      remote: remote,
      local: local,
      fallbackRemoteName: "Call",
      fallbackLocalName: "You"
    )
    callView.frame = view.bounds
    callView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(callView)
  }

  private func initials(from name: String) -> String {
    let parts = name
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }
    guard let first = parts.first else { return "?" }
    guard let last = parts.dropFirst().last else {
      return String(first.prefix(1)).uppercased()
    }
    return "\(first.prefix(1))\(last.prefix(1))".uppercased()
  }

  private func color(for key: String) -> UIColor {
    let colors = [
      UIColor(red: 0.12, green: 0.20, blue: 0.28, alpha: 1.0),
      UIColor(red: 0.16, green: 0.26, blue: 0.22, alpha: 1.0),
      UIColor(red: 0.24, green: 0.18, blue: 0.30, alpha: 1.0),
      UIColor(red: 0.26, green: 0.22, blue: 0.16, alpha: 1.0)
    ]
    let index = abs(key.hashValue) % colors.count
    return colors[index]
  }

  private func activeRootView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }

    let keyWindow = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }

    return keyWindow?.rootViewController?.view
  }

  private func enterPictureInPicture(result: @escaping FlutterResult) {
    guard
      let controller = pipController,
      AVPictureInPictureController.isPictureInPictureSupported()
    else {
      setLastError("Cannot enter iOS PiP: unsupported device/runtime or no prepared native PiP content.")
      emitPipMode(false)
      result(false)
      return
    }

    if controller.isPictureInPictureActive {
      lastError = nil
      emitPipMode(true)
      result(true)
      return
    }

    if let player = player {
      activateAudioSession(category: .playback, mode: .moviePlayback)
      prepareToStartPictureInPicture(player: player, controller: controller, result: result)
      return
    }

    activateAudioSession(category: .playAndRecord, mode: .videoChat)
    startPictureInPicture(controller: controller, result: result)
  }

  private func prepareToStartPictureInPicture(
    player: AVPlayer,
    controller: AVPictureInPictureController,
    result: @escaping FlutterResult
  ) {
    guard let item = player.currentItem else {
      setLastError("Cannot enter iOS PiP: AVPlayer has no current item.")
      emitPipMode(false)
      result(false)
      return
    }

    waitUntilPlayerItemIsReady(player: player, item: item) { [weak self, weak player, weak controller] isReady in
      guard
        let self = self,
        let player = player,
        let controller = controller
      else {
        result(false)
        return
      }

      guard isReady else {
        self.setLastError("Cannot enter iOS PiP: AVPlayerItem did not become ready.")
        self.emitPipMode(false)
        result(false)
        return
      }

      self.startPictureInPicture(player: player, controller: controller, result: result)
    }
  }

  private func startPictureInPicture(
    player: AVPlayer,
    controller: AVPictureInPictureController,
    result: @escaping FlutterResult
  ) {
    player.play()
    startPictureInPicture(controller: controller, result: result)
  }

  private func startPictureInPicture(
    controller: AVPictureInPictureController,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak controller] in
      guard let self = self, let controller = controller else {
        result(false)
        return
      }

      self.waitUntilPictureInPictureIsPossible(controller: controller) { [weak self] isPossible in
        guard let self = self else {
          result(false)
          return
        }

        guard isPossible else {
          self.setLastError("Cannot enter iOS PiP: AVKit reports isPictureInPicturePossible=false.")
          self.emitPipMode(false)
          result(false)
          return
        }

        self.pendingStartResult = result
        self.pendingStartTimeout?.invalidate()
        self.pendingStartTimeout = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self, weak controller] _ in
          guard let self = self, let controller = controller else { return }
          if let pending = self.pendingStartResult {
            if controller.isPictureInPictureActive {
              self.lastError = nil
              self.pendingStartResult = nil
              self.emitPipMode(true)
              pending(true)
              return
            }
            self.setLastError("iOS PiP start timed out before AVKit confirmed didStart.")
            self.pendingStartResult = nil
            self.emitPipMode(false)
            pending(false)
          }
        }

        controller.startPictureInPicture()
      }
    }
  }

  private func activateAudioSession(
    category: AVAudioSession.Category,
    mode: AVAudioSession.Mode
  ) {
    do {
      try AVAudioSession.sharedInstance().setCategory(category, mode: mode)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      setLastError("iOS could not activate the audio session: \(error.localizedDescription)")
    }
  }

  private func waitUntilPictureInPictureIsPossible(
    controller: AVPictureInPictureController,
    attempt: Int = 0,
    completion: @escaping (Bool) -> Void
  ) {
    if controller.isPictureInPicturePossible {
      completion(true)
      return
    }

    if attempt >= 20 {
      completion(false)
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak controller] in
      guard let controller = controller else {
        completion(false)
        return
      }
      self.waitUntilPictureInPictureIsPossible(
        controller: controller,
        attempt: attempt + 1,
        completion: completion
      )
    }
  }

  private func waitUntilPlayerItemIsReady(
    player: AVPlayer,
    item: AVPlayerItem,
    attempt: Int = 0,
    completion: @escaping (Bool) -> Void
  ) {
    switch item.status {
    case .readyToPlay:
      completion(true)
    case .failed:
      setLastError("AVPlayerItem failed: \(item.error?.localizedDescription ?? "Unknown playback error").")
      completion(false)
    case .unknown:
      if attempt >= 50 {
        completion(false)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak player, weak item] in
        guard let player = player, let item = item, player.currentItem === item else {
          completion(false)
          return
        }
        self.waitUntilPlayerItemIsReady(
          player: player,
          item: item,
          attempt: attempt + 1,
          completion: completion
        )
      }
    @unknown default:
      completion(false)
    }
  }

  private func exitPictureInPicture() -> Bool {
    guard let controller = pipController else {
      emitPipMode(false)
      return false
    }

    if controller.isPictureInPictureActive {
      controller.stopPictureInPicture()
      emitPipMode(false)
      return true
    }

    emitPipMode(false)
    return false
  }

  private func clearNativeContent(
    resetError: Bool = true,
    emitInactive: Bool = true
  ) {
    finishPendingStart(false)
    if resetError {
      lastError = nil
    }
    if pipController?.isPictureInPictureActive == true {
      pipController?.stopPictureInPicture()
    }
    pipController?.delegate = nil
    pipController = nil
    player?.pause()
    player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    playerHostView?.removeFromSuperview()
    playerHostView = nil
    callSourceView?.removeFromSuperview()
    callSourceView = nil
    callViewController = nil
    sourceRectHint = nil
    activeContentKey = nil
    if emitInactive {
      emitPipMode(false)
    }
  }

  private func emitPipMode(_ isActive: Bool) {
    eventSink?(isActive)
  }

  private func setLastError(_ message: String) {
    lastError = message
    NSLog("[universal_pip] \(message)")
  }

  private func finishPendingStart(_ didStart: Bool) {
    pendingStartTimeout?.invalidate()
    pendingStartTimeout = nil
    if let pending = pendingStartResult {
      pendingStartResult = nil
      pending(didStart)
    }
  }

  public func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    lastError = nil
    emitPipMode(true)
  }

  public func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    lastError = nil
    emitPipMode(true)
    finishPendingStart(true)
  }

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    setLastError("iOS PiP failed to start: \(error.localizedDescription)")
    emitPipMode(false)
    finishPendingStart(false)
  }

  public func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {}

  public func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    emitPipMode(false)
  }
}

private struct NativePipParticipant {
  let id: String
  let displayName: String
  let avatarUrl: String?
  let isLocal: Bool
  let isMuted: Bool
  let isCameraEnabled: Bool

  var cacheKey: String {
    [
      id,
      displayName,
      avatarUrl ?? "",
      String(isLocal),
      String(isMuted),
      String(isCameraEnabled)
    ].joined(separator: ",")
  }
}

private final class NativePipVideoCallView: UIView {
  private let remoteView: NativePipParticipantTile
  private let localView: NativePipParticipantTile?

  init(
    remote: NativePipParticipant?,
    local: NativePipParticipant?,
    fallbackRemoteName: String,
    fallbackLocalName: String
  ) {
    remoteView = NativePipVideoCallView.makeParticipantView(
      participant: remote,
      fallbackName: fallbackRemoteName,
      isCompact: false
    )

    if let local = local {
      localView = NativePipVideoCallView.makeParticipantView(
        participant: local,
        fallbackName: fallbackLocalName,
        isCompact: true
      )
    } else {
      localView = nil
    }

    super.init(frame: .zero)

    backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1.0)
    addSubview(remoteView)

    if let localView = localView {
      localView.layer.borderColor = UIColor.white.withAlphaComponent(0.30).cgColor
      localView.layer.borderWidth = 1
      localView.clipsToBounds = true
      addSubview(localView)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    remoteView.frame = bounds

    guard let localView = localView else { return }

    let width = max(bounds.width, 1)
    let height = max(bounds.height, 1)
    let localWidth = min(max(width * 0.18, 44), 60)
    let localHeight = localWidth * 1.20
    let inset = min(max(width * 0.035, 6), 10)
    localView.frame = CGRect(
      x: max(width - localWidth - inset, inset),
      y: max(height - localHeight - inset, inset),
      width: localWidth,
      height: localHeight
    )
    localView.layer.cornerRadius = min(10, localWidth * 0.16)
  }

  private static func makeParticipantView(
    participant: NativePipParticipant?,
    fallbackName: String,
    isCompact: Bool
  ) -> NativePipParticipantTile {
    let displayName = participant?.displayName ?? fallbackName
    return NativePipParticipantTile(
      displayName: displayName,
      initials: initials(from: displayName),
      isMuted: participant?.isMuted == true,
      isCompact: isCompact,
      backgroundColor: participant?.isCameraEnabled == true
      ? color(for: participant?.id ?? displayName)
      : UIColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1.0)
    )
  }

  private static func initials(from name: String) -> String {
    let parts = name
      .split(separator: " ")
      .map(String.init)
      .filter { !$0.isEmpty }
    guard let first = parts.first else { return "?" }
    guard let last = parts.dropFirst().last else {
      return String(first.prefix(1)).uppercased()
    }
    return "\(first.prefix(1))\(last.prefix(1))".uppercased()
  }

  private static func color(for key: String) -> UIColor {
    let colors = [
      UIColor(red: 0.12, green: 0.20, blue: 0.28, alpha: 1.0),
      UIColor(red: 0.16, green: 0.26, blue: 0.22, alpha: 1.0),
      UIColor(red: 0.24, green: 0.18, blue: 0.30, alpha: 1.0),
      UIColor(red: 0.26, green: 0.22, blue: 0.16, alpha: 1.0)
    ]
    let index = abs(key.hashValue) % colors.count
    return colors[index]
  }
}

private final class NativePipParticipantTile: UIView {
  private let initialsLabel = UILabel()
  private let nameLabel = UILabel()
  private let mutedLabel = UILabel()
  private let isCompact: Bool

  init(
    displayName: String,
    initials: String,
    isMuted: Bool,
    isCompact: Bool,
    backgroundColor: UIColor
  ) {
    self.isCompact = isCompact
    super.init(frame: .zero)

    self.backgroundColor = backgroundColor

    initialsLabel.text = initials
    initialsLabel.textColor = .white
    initialsLabel.textAlignment = .center
    initialsLabel.font = .systemFont(ofSize: isCompact ? 18 : 42, weight: .bold)
    initialsLabel.backgroundColor = UIColor.white.withAlphaComponent(0.14)
    initialsLabel.clipsToBounds = true
    addSubview(initialsLabel)

    nameLabel.text = displayName
    nameLabel.textColor = UIColor.white.withAlphaComponent(0.92)
    nameLabel.textAlignment = .center
    nameLabel.font = .systemFont(ofSize: isCompact ? 11 : 17, weight: .semibold)
    nameLabel.numberOfLines = isCompact ? 1 : 2
    addSubview(nameLabel)

    mutedLabel.text = isMuted ? "Muted" : nil
    mutedLabel.textColor = UIColor.white.withAlphaComponent(0.78)
    mutedLabel.textAlignment = .center
    mutedLabel.font = .systemFont(ofSize: isCompact ? 9 : 12, weight: .medium)
    mutedLabel.isHidden = !isMuted
    addSubview(mutedLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    let width = max(bounds.width, 1)
    let height = max(bounds.height, 1)
    let avatarSize = min(isCompact ? 44 : 88, width * 0.5, height * 0.42)
    let avatarY = max((height - avatarSize) / 2 - (isCompact ? 8 : 16), 8)
    initialsLabel.frame = CGRect(
      x: (width - avatarSize) / 2,
      y: avatarY,
      width: avatarSize,
      height: avatarSize
    )
    initialsLabel.layer.cornerRadius = avatarSize / 2

    let horizontalInset = min(CGFloat(12), width / 4)
    let labelWidth = max(width - horizontalInset * 2, 1)
    let nameHeight = isCompact ? CGFloat(16) : CGFloat(44)
    nameLabel.frame = CGRect(
      x: horizontalInset,
      y: initialsLabel.frame.maxY + (isCompact ? 6 : 14),
      width: labelWidth,
      height: nameHeight
    )

    mutedLabel.frame = CGRect(
      x: horizontalInset,
      y: nameLabel.frame.maxY + 4,
      width: labelWidth,
      height: isCompact ? 12 : 16
    )
  }
}
