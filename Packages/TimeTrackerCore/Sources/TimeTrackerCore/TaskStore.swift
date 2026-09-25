import Foundation
import Observation

/// The single source of truth for the task list, its selection, and which row
/// is being edited.
///
/// `@Observable` (macOS 14+) lets SwiftUI views read these properties directly
/// and redraw when they change — no `@Published` or `objectWillChange` needed.
///
/// `@MainActor` because the UI owns it; that also makes the mutations
/// serialized without any locking.
///
/// Every mutation saves synchronously. The file is tiny, so this trades an
/// immeasurable amount of time for never losing a change to a crash or a
/// force-quit.
@MainActor
@Observable
public final class TaskStore {
  public private(set) var tasks: [TrackedTask]
  /// The keyboard-highlighted row, if any.
  public var selectedID: UUID?
  /// The row currently showing the inline editor, if any.
  public var editingID: UUID?

  /// The inline editor's field text, reseeded every time an editor opens.
  ///
  /// These live here rather than in the editor view's `@State`: SwiftUI keeps
  /// `@State` whenever it reuses a view's identity and then ignores the new
  /// seed, which showed a task's time from an earlier edit (for example, a
  /// time from before the task was reset).
  public var draftTitle = ""
  public var draftDuration = ""

  /// A running task is banked and temporarily paused while it is edited.
  /// This is intentionally transient: it lets commit/cancel resume only a
  /// task that was running before editing, without changing the persisted
  /// task model or treating a user-stopped task as resumable.
  private var pausedEditingID: UUID?

  private let persistence: any TaskPersisting
  /// Injectable "now" in epoch milliseconds, so tests control time exactly.
  private let now: @Sendable () -> Int

  public init(
    persistence: any TaskPersisting,
    now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.persistence = persistence
    self.now = now
    self.tasks = persistence.load()
  }

  // MARK: - Derived state

  /// True while at least one timer is counting. Drives the red menu bar tint
  /// and whether the per-second clock needs to run at all.
  public var anyRunning: Bool {
    tasks.contains(where: \.running)
  }

  /// The combined time across all tasks, right now.
  public var totalSecondsNow: Int {
    totalSeconds(tasks, nowMs: now())
  }

  /// Display seconds for one task at an arbitrary instant. Views pass the
  /// shared clock's `now` so every row and the total agree within a frame.
  public func elapsed(_ task: TrackedTask, at nowMs: Int) -> Int {
    elapsedSeconds(task, nowMs: nowMs)
  }

  // MARK: - Mutations

  /// Appends a blank task, selects it, and opens its editor so the user can
  /// type a title straight away.
  public func add() {
    // ⌘N is still available from inside the editor. Finish the previous
    // edit's temporary pause before replacing it with the new editor.
    if editingID != nil {
      cancelEdit()
    }

    let task = TrackedTask(title: "Empty")
    tasks.append(task)
    selectedID = task.id
    openEditor(at: tasks.count - 1)
    save()
  }

  /// Starts a stopped task, or stops a running one and banks its time.
  /// Any number of tasks may run at once.
  public func toggle(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    let timestamp = now()

    if tasks[index].running {
      tasks[index].seconds = elapsedSeconds(tasks[index], nowMs: timestamp)
      tasks[index].running = false
      tasks[index].startedAt = 0
    } else {
      tasks[index].running = true
      tasks[index].startedAt = timestamp
    }
    save()
  }

  /// Zeroes one task's timer. A running task keeps running, counting up from zero.
  public func reset(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].seconds = 0
    if tasks[index].running {
      tasks[index].startedAt = now()
    }
    save()
  }

  /// Zeroes every task, leaving running ones running.
  public func resetAll() {
    let timestamp = now()
    for index in tasks.indices {
      tasks[index].seconds = 0
      if tasks[index].running {
        tasks[index].startedAt = timestamp
      }
    }
    save()
  }

  /// Removes a task and moves the selection to a sensible neighbor: the task
  /// that slid into its place, or the one before it when deleting the last row.
  public func delete(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks.remove(at: index)

    if editingID == id {
      editingID = nil
      pausedEditingID = nil
    }
    if selectedID == id {
      if tasks.isEmpty {
        selectedID = nil
      } else {
        selectedID = tasks[min(index, tasks.count - 1)].id
      }
    }
    save()
  }

  /// Applies the inline editor's fields and closes it.
  ///
  /// A duration that cannot be parsed leaves the stored time untouched, so a
  /// typo never silently destroys tracked hours — the title still applies.
  ///
  /// A task that was running when editing began resumes from the edited
  /// duration. A task that was already stopped remains stopped.
  public func commitEdit(_ id: UUID, title: String, durationText: String) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    tasks[index].title = trimmed.isEmpty ? "Empty" : trimmed

    if let seconds = parseDuration(durationText) {
      tasks[index].seconds = seconds
    }

    let wasPausedForEditing = pausedEditingID == id
    if wasPausedForEditing {
      tasks[index].running = true
      tasks[index].startedAt = now()
    } else if tasks[index].running {
      // Keep this method safe for callers that commit without opening the
      // inline editor first.
      tasks[index].startedAt = now()
    }

    pausedEditingID = nil
    editingID = nil
    save()
  }

  /// Closes the editor without applying anything.
  public func cancelEdit() {
    guard let id = editingID else { return }

    if pausedEditingID == id,
      let index = tasks.firstIndex(where: { $0.id == id })
    {
      tasks[index].running = true
      tasks[index].startedAt = now()
      pausedEditingID = nil
      save()
    } else {
      pausedEditingID = nil
    }

    editingID = nil
  }

  /// Opens the editor on a task.
  ///
  /// Editing temporarily pauses a running timer. Bank the elapsed time before
  /// replacing the row with the editor so the duration field starts at the
  /// exact value the user saw. The task resumes when the edit is committed or
  /// cancelled; any other running tasks continue normally.
  public func beginEdit(_ id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

    if editingID != nil, editingID != id {
      cancelEdit()
    }

    selectedID = id
    if tasks[index].running {
      tasks[index].seconds = elapsedSeconds(tasks[index], nowMs: now())
      tasks[index].running = false
      tasks[index].startedAt = 0
      pausedEditingID = id
    }
    openEditor(at: index)

    if pausedEditingID == id {
      save()
    }
  }

  /// Seeds the drafts from what the row shows. The task is stopped (or was
  /// just banked) by now, so its elapsed time is exactly its stored seconds.
  private func openEditor(at index: Int) {
    draftTitle = tasks[index].title
    draftDuration = formatDuration(elapsedSeconds(tasks[index], nowMs: now()))
    editingID = tasks[index].id
  }

  /// Moves the keyboard selection by `offset` rows, clamped at both ends.
  /// With nothing selected, moving down lands on the first row and up on the last.
  public func moveSelection(by offset: Int) {
    guard !tasks.isEmpty else { return }

    guard let current = selectedID, let index = tasks.firstIndex(where: { $0.id == current }) else {
      selectedID = offset > 0 ? tasks.first?.id : tasks.last?.id
      return
    }
    let target = min(max(index + offset, 0), tasks.count - 1)
    selectedID = tasks[target].id
  }

  private func save() {
    persistence.save(tasks)
  }
}
