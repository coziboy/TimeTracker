import SwiftUI
import TimeTrackerCore

/// The strip along the bottom: combined total, Reset All, Add, and the gear menu.
struct FooterBar: View {
  let total: Int
  let launchAtLogin: LaunchAtLogin

  let onResetAll: () -> Void
  let onAdd: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text("Total: \(formatDuration(total))")
        .monospacedDigit()
        .foregroundStyle(.secondary)

      Spacer()

      Button("Reset All", action: onResetAll)
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(.secondary)
        .help("Set every task back to zero")

      Button(action: onAdd) {
        Image(systemName: "plus")
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .help("Add a task (⌘N)")

      gearMenu
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var gearMenu: some View {
    Menu {
      Button {
        // An approval-pending state cannot be resolved in-app; send the user
        // to the one place macOS lets them finish it.
        if launchAtLogin.requiresApproval {
          launchAtLogin.openLoginItemsSettings()
        } else {
          launchAtLogin.toggle()
        }
      } label: {
        // A checkmark reads as state; plain text reads as an action.
        Label(
          "Launch at Login",
          systemImage: launchAtLogin.isEnabled ? "checkmark" : "")
      }
      .disabled(!launchAtLogin.isAvailable)

      if let explanation = launchAtLogin.explanation {
        Text(explanation)
      }

      Divider()

      // Shortcuts live here because the plan dropped the help overlay; this
      // is the one place a user is likely to go looking.
      Text("↑↓ select · Space start/stop · ⏎ edit · ⌫ delete · ⌘N add")

      Divider()

      Button("Quit TimeTracker") {
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q")
    } label: {
      Image(systemName: "gearshape")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .focusable(false)
    .help("Settings")
    // The menu reads a status that can change outside the app, so refresh it
    // as the popover appears rather than trusting a value cached at launch.
    .onAppear { launchAtLogin.refresh() }
  }
}
