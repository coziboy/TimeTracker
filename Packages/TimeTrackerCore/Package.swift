// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TimeTrackerCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"])
  ],
  targets: [
    .target(name: "TimeTrackerCore"),
    .testTarget(name: "TimeTrackerCoreTests", dependencies: ["TimeTrackerCore"]),
  ],
  swiftLanguageModes: [.v6]
)
