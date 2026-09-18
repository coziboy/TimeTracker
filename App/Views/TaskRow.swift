import SwiftUI
import TimeTrackerCore

/// One task in the list: status dot, title, elapsed time, and — on hover or
/// when selected — four icon actions.
///
/// The row is deliberately *not* a `Button`. A Button would claim Space and
/// Return for itself, which would double-fire alongside our key monitor.
/// `contentShape` + `onTapGesture` gives the same click target with none of
/// that behavior.
struct TaskRow: View {
  let task: TrackedTask
  let elapsed: Int
  let isSelected: Bool

  let onToggle: () -> Void
  let onReset: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  @State private var isHovering = false

  /// Actions appear on hover or for the keyboard-selected row, so the list
  /// stays quiet at rest but is always reachable without the mouse.
  private var showsActions: Bool { isHovering || isSelected }

  var body: some View {
    HStack(spacing: 10) {
      // Filled while running, hollow while idle — the same language as the
      // original widget, readable at a glance without reading the numbers.
      Image(systemName: task.running ? "circle.fill" : "circle")
        .font(.system(size: 9))
        .foregroundStyle(task.running ? Color.accentColor : .secondary)

      Text(task.title)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(task.running ? .primary : .secondary)

      Spacer(minLength: 8)

      if showsActions {
        actions
      }

      Text(formatDuration(elapsed))
        // Monospaced digits keep the column from twitching as seconds tick.
        .monospacedDigit()
        .foregroundStyle(task.running ? .primary : .secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.primary.opacity(0.08) : .clear)
    )
    // Makes the whole row clickable, including the empty space in the middle.
    .contentShape(Rectangle())
    .onTapGesture(perform: onToggle)
    .onHover { isHovering = $0 }
  }

  private var actions: some View {
    HStack(spacing: 2) {
      actionButton(
        task.running ? "pause.fill" : "play.fill",
        help: task.running ? "Pause" : "Start",
        action: onToggle)
      actionButton("arrow.counterclockwise", help: "Reset", action: onReset)
      actionButton("pencil", help: "Edit", action: onEdit)
      actionButton("trash", help: "Delete", action: onDelete)
    }
  }

  private func actionButton(
    _ symbol: String, help: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11))
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Without this the buttons would take keyboard focus and Space/Return
    // would press them as well as running our own key command.
    .focusable(false)
    .help(help)
  }
}
