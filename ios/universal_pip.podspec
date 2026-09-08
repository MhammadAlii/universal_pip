#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint universal_pip.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'universal_pip'
  s.version          = '0.0.1'
  s.summary          = 'Universal Flutter Picture-in-Picture controller.'
  s.description      = <<-DESC
Universal Flutter Picture-in-Picture controller with draggable in-app PiP,
Android system PiP, and safe iOS/web fallbacks.
                       DESC
  s.homepage         = 'https://github.com/mo-dev/universal_pip'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Shared with the Swift package in `universal_pip/`, so a CocoaPods app and a
  # Swift Package Manager app build the exact same sources.
  s.source_files = 'universal_pip/Sources/**/*.{swift,h,m}'
  s.public_header_files = 'universal_pip/Sources/universal_pip_bridge/include/**/*.h'
  s.resource_bundles = {
    'universal_pip_privacy' => ['universal_pip/Sources/universal_pip/Resources/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  # Version intentionally unconstrained: the host app (via flutter_webrtc) owns the
  # WebRTC-SDK version. Pinning here causes an unresolvable CocoaPods conflict
  # whenever the app's flutter_webrtc pins a different build. This plugin only
  # needs the headers to compile; it resolves everything at runtime through the
  # app's FlutterWebRTCPlugin singleton.
  s.dependency 'WebRTC-SDK'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

end
