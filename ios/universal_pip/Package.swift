// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "universal_pip",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        // Hyphenated because Swift Package Manager uses a dynamically linked
        // library's name as its CFBundleIdentifier, which cannot contain
        // underscores. Flutter looks the product up under this exact name.
        .library(name: "universal-pip", targets: ["universal_pip"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // WebRTC comes from flutter_webrtc's exported `WebRTC` product rather
        // than a binary target of our own: two packages vendoring the same
        // xcframework both embed WebRTC.framework into the app bundle, which
        // fails the build with "Multiple commands produce ... WebRTC.framework".
        // The unversioned path is deliberate — Flutter rewrites it to the
        // resolved version (e.g. "../flutter_webrtc-1.6.1") when it generates
        // the app's package graph.
        .package(name: "flutter_webrtc", path: "../flutter_webrtc")
    ],
    targets: [
        // Swift and Objective-C cannot share one Swift Package Manager target,
        // so the WebRTC bridge is its own module. Under CocoaPods both files
        // still compile into a single pod, where the header is reachable
        // through the umbrella header instead.
        .target(
            name: "universal_pip_bridge",
            dependencies: [
                .product(name: "WebRTC", package: "flutter_webrtc")
            ]
        ),
        .target(
            name: "universal_pip",
            dependencies: [
                "universal_pip_bridge",
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("Resources/PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
