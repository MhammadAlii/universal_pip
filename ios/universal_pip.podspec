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
  s.source_files = 'universal_pip/Sources/universal_pip/**/*.swift'
  s.resource_bundles = {
    'universal_pip_privacy' => ['universal_pip/Sources/universal_pip/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

end
