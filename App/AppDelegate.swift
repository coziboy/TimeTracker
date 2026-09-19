import AppKit
import TimeTrackerCore

/// Owns the app's long-lived objects and wires them together at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Menu-bar apps have no normal window lifecycle to prevent duplicate
    // launches. Leave the already-running instance in place instead of
    // creating a second status item whenever the app is opened again.
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let alreadyRunning = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
    ).contains { $0.processIdentifier != currentPID }
    if alreadyRunning {
      NSApp.terminate(nil)
      return
    }

    // Loading happens here, in TaskStore's initializer, reading the JSON file.
    let store = TaskStore(persistence: JSONFilePersistence())
    let clock = Clock()
    statusItemController = StatusItemController(
      store: store, clock: clock, launchAtLogin: LaunchAtLogin())
  }
}
