import SwiftUI

/// The app entry point.
///
/// There is deliberately no `WindowGroup`: every pixel of UI lives in the
/// menu bar popover, which `AppDelegate` builds with AppKit. `Settings` with an
/// empty view satisfies SwiftUI's requirement that an `App` declare *some*
/// scene, while opening no window on launch.
///
/// Combined with `LSUIElement` in Info.plist, this makes a true agent app:
/// no Dock icon, no menu bar menus, just the status item.
@main
struct TimeTrackerApp: App {
  // Bridges an AppKit delegate into the SwiftUI lifecycle so we can build
  // NSStatusItem/NSPopover, which SwiftUI's MenuBarExtra cannot do well enough
  // here (it can't make its window key, which breaks keyboard input).
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
