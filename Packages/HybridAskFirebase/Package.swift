// swift-tools-version:6.2
// HybridAskFirebase: plugs Firebase AI Logic hybrid inference into HybridAskCore.
// Apple's on-device model first, a cloud Gemini model as fallback.
import PackageDescription

let package = Package(
  name: "HybridAskFirebase",
  platforms: [.iOS(.v26)],
  products: [
    .library(name: "HybridAskFirebase", targets: ["HybridAskFirebase"]),
  ],
  dependencies: [
    .package(path: "../HybridAskCore"),
    .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.13.0"),
  ],
  targets: [
    .target(
      name: "HybridAskFirebase",
      dependencies: [
        .product(name: "HybridAskCore", package: "HybridAskCore"),
        .product(name: "FirebaseAILogic", package: "firebase-ios-sdk"),
      ]
    ),
  ]
)
