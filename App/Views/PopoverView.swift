import SwiftUI
import TimeTrackerCore

/// The popover's whole contents: the task list (or empty state) above the footer.
struct PopoverView: View {
  @Bindable var store: TaskStore
  let clock: Clock
  let controller: StatusItemController
  let launchAtLogin: LaunchAtLogin

  /// Keeps the popover from growing without bound once there are many tasks;
  /// the list scrolls past this point.
  private let maxListHeight: CGFloat = 320

  var body: some View {
    VStack(spacing: 0) {
      if store.tasks.isEmpty {
        EmptyStateView()
      } else {
        list
      }

      Divider()

      FooterBar(
        total: totalSeconds(store.tasks, nowMs: clock.now),
        launchAtLogin: launchAtLogin,
        onResetAll: {
          store.resetAll()
          controller.updateClockPolicy()
        },
        onAdd: { store.add() }
      )
    }
    .frame(width: 420)
  }

  /// A ScrollView + LazyVStack rather than a `List`, because `List` swallows
  /// the arrow keys for its own selection and would fight our key monitor.
  private var list: some View {
    ScrollView {
      LazyVStack(spacing: 2) {
        ForEach(store.tasks) { task in
          row(for: task)
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 6)
    }
    .frame(maxHeight: maxListHeight)
    // Let the popover shrink to fit a short list instead of always reserving
    // the full height.
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func row(for task: TrackedTask) -> some View {
    let elapsed = elapsedSeconds(task, nowMs: clock.now)

    if store.editingID == task.id {
      InlineEditor(
        title: $store.draftTitle,
        duration: $store.draftDuration,
        onCommit: { title, duration in
          store.commitEdit(task.id, title: title, durationText: duration)
          controller.updateClockPolicy()
        },
        onCancel: {
          store.cancelEdit()
          controller.updateClockPolicy()
        }
      )
    } else {
      TaskRow(
        task: task,
        elapsed: elapsed,
        isSelected: store.selectedID == task.id,
        onToggle: {
          store.selectedID = task.id
          store.toggle(task.id)
          controller.updateClockPolicy()
        },
        onReset: {
          store.reset(task.id)
          controller.updateClockPolicy()
        },
        onEdit: {
          store.beginEdit(task.id)
          controller.updateClockPolicy()
        },
        onDelete: {
          store.delete(task.id)
          controller.updateClockPolicy()
        }
      )
    }
  }
}
