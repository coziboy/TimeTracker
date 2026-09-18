import AppKit
import SwiftUI

/// The gear button, backed by a real `NSMenu` rather than SwiftUI's `Menu`.
///
/// SwiftUI's `Menu` opens its own window. Inside a `.transient` NSPopover the
/// popover reads that as a click elsewhere and begins dismissing itself, so the
/// menu is left hanging over whatever is behind the app — the glitch this
/// replaces. Popping an NSMenu from the button keeps the interaction inside
/// AppKit, which knows the popover and the menu belong together.
struct GearMenuButton: NSViewRepresentable {
  let launchAtLogin: LaunchAtLogin

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton()
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
    button.imagePosition = .imageOnly
    button.target = context.coordinator
    button.action = #selector(Coordinator.showMenu(_:))
    button.toolTip = "Settings"
    // Stops Space and Return from activating this instead of the selected row.
    button.refusesFirstResponder = true
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.launchAtLogin = launchAtLogin
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(launchAtLogin: launchAtLogin)
  }

  @MainActor
  final class Coordinator: NSObject {
    var launchAtLogin: LaunchAtLogin

    init(launchAtLogin: LaunchAtLogin) {
      self.launchAtLogin = launchAtLogin
    }

    @objc func showMenu(_ sender: NSButton) {
      // The status can change outside the app, so read it as the menu opens
      // rather than trusting whatever was cached earlier.
      launchAtLogin.refresh()

      let menu = NSMenu()

      let loginItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: "")
      loginItem.target = self
      loginItem.state = launchAtLogin.isEnabled ? .on : .off
      menu.addItem(loginItem)

      if let explanation = launchAtLogin.explanation {
        let note = NSMenuItem(title: explanation, action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
      }

      menu.addItem(.separator())

      // Shortcuts live here because the plan dropped the help overlay; this is
      // the one place a user is likely to go looking for them.
      let shortcuts = NSMenuItem(
        title: "↑↓ select · Space start/stop · ⏎ edit · ⌫ delete · ⌘N add",
        action: nil, keyEquivalent: "")
      shortcuts.isEnabled = false
      menu.addItem(shortcuts)

      menu.addItem(.separator())

      let quit = NSMenuItem(
        title: "Quit TimeTracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
      menu.addItem(quit)

      // Pop below the button so the menu never covers the row it belongs to.
      menu.popUp(
        positioning: nil,
        at: NSPoint(x: 0, y: sender.bounds.height + 4),
        in: sender)
    }

    @objc private func toggleLaunchAtLogin() {
      // A pending approval cannot be resolved in-app; send the user to the one
      // place macOS lets them finish it.
      if launchAtLogin.requiresApproval {
        launchAtLogin.openLoginItemsSettings()
      } else {
        launchAtLogin.toggle()
      }
    }
  }
}
