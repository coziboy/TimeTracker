import AppKit
import TimeTrackerCore

/// Owns the app's long-lived objects and wires them together at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItemController: StatusItemController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Loading happens here, in TaskStore's initializer, reading the JSON file.
    let store = TaskStore(persistence: JSONFilePersistence())
    let clock = Clock()
    statusItemController = StatusItemController(
      store: store, clock: clock, launchAtLogin: LaunchAtLogin())
  }
}
