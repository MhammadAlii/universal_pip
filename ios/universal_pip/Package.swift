// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "universal_pip",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "universal-pip", targets: ["universal_pip"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "universal_pip",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    )
  ]
)
