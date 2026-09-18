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

      GearMenuButton(launchAtLogin: launchAtLogin)
        .frame(width: 22, height: 22)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

}
