import SwiftUI
import TimeTrackerCore

/// The popover's whole contents: the search field and task list (or empty
/// state) above the footer.
struct PopoverView: View {
  @Bindable var store: TaskStore
  let clock: Clock
  let controller: StatusItemController
  let launchAtLogin: LaunchAtLogin
  let searchFocus: SearchFocus

  /// Keeps the popover from growing without bound once there are many tasks;
  /// the list scrolls past this point.
  private let maxListHeight: CGFloat = 320

  var body: some View {
    VStack(spacing: 0) {
      if store.tasks.isEmpty {
        EmptyStateView()
      } else {
        SearchField(query: $store.searchQuery, sortOrder: $store.sortOrder, focus: searchFocus)

        if store.visibleTasks.isEmpty {
          Text("No matching tasks")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
          list
        }
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
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(store.visibleTasks) { task in
            row(for: task)
              .id(task.id)
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
      }
      // Keep the keyboard-selected row in view; a nil anchor scrolls only as
      // far as needed to reveal it.
      .onChange(of: store.selectedID) { _, id in
        guard let id else { return }
        scrollTo(id, using: proxy)
      }
      // Adding a task selects it before SwiftUI has inserted its row. Once
      // the editor closes, the row has its final sorted position; reveal it
      // again so submitting a new task leaves that task in view and selected.
      .onChange(of: store.editingID) { oldID, newID in
        guard oldID != nil, newID == nil, let id = store.selectedID else { return }
        scrollTo(id, using: proxy)
      }
    }
    .frame(maxHeight: maxListHeight)
    // Let the popover shrink to fit a short list instead of always reserving
    // the full height.
    .fixedSize(horizontal: false, vertical: true)
  }

  private func scrollTo(_ id: UUID, using proxy: ScrollViewProxy) {
    // Let SwiftUI apply list insertion/reordering before resolving the target.
    DispatchQueue.main.async {
      proxy.scrollTo(id)
    }
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
