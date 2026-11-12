// swift-tools-version:6.0
// HybridAskCore: the honest part of Ask, with no AI SDK in it.
// Prompt rules, answer checks, fixed replies and the saved-question record.
// Any model (on-device, cloud, or both) plugs in through `AskModel`.
import PackageDescription

let package = Package(
  name: "HybridAskCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "HybridAskCore", targets: ["HybridAskCore"]),
  ],
  targets: [
    .target(name: "HybridAskCore", resources: [.copy("Resources/eval-cases.json")]),
    .testTarget(name: "HybridAskCoreTests", dependencies: ["HybridAskCore"]),
  ]
)
