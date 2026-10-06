// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TimeTrackerCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
    .library(name: "TimeTrackerCLI", targets: ["TimeTrackerCLI"]),
    .executable(name: "timetracker", targets: ["timetracker"]),
  ],
  targets: [
    .target(name: "TimeTrackerCore"),
    // Parsing and running CLI commands, kept out of `main.swift` so it is testable.
    .target(name: "TimeTrackerCLI", dependencies: ["TimeTrackerCore"]),
    .executableTarget(name: "timetracker", dependencies: ["TimeTrackerCLI"]),
    .testTarget(name: "TimeTrackerCoreTests", dependencies: ["TimeTrackerCore"]),
    .testTarget(name: "TimeTrackerCLITests", dependencies: ["TimeTrackerCLI"]),
  ],
  swiftLanguageModes: [.v6]
)
