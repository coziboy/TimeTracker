import Foundation
import Testing
@testable import TimeTrackerCore

/// A movable clock so time-dependent behavior is exact rather than racy.
private final class FakeClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int
  init(_ value: Int) { self.value = value }
  var now: Int { lock.withLock { value } }
  func advance(ms: Int) { lock.withLock { value += ms } }
}

@MainActor
private func makeStore(
  tasks: [TrackedTask] = [],
  nowMs: Int = 1_000_000
) -> (TaskStore, FakeClock, InMemoryPersistence) {
  let clock = FakeClock(nowMs)
  let persistence = InMemoryPersistence(tasks: tasks)
  let store = TaskStore(persistence: persistence, now: { clock.now })
  return (store, clock, persistence)
}

@Suite("TaskStore.add")
@MainActor
struct AddTests {
  @Test("add appends an Empty task at zero and opens it for editing")
  func addAppends() {
    let (store, _, _) = makeStore()
    store.add()

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].title == "Empty")
    #expect(store.tasks[0].seconds == 0)
    #expect(store.tasks[0].running == false)
    #expect(store.selectedID == store.tasks[0].id)
    #expect(store.editingID == store.tasks[0].id)
    #expect(store.draftTitle == "Empty")
    #expect(store.draftDuration == "00:00:00")
  }

  @Test("add persists immediately")
  func addSaves() {
    let (store, _, persistence) = makeStore()
    store.add()
    #expect(persistence.load().count == 1)
  }
}

@Suite("TaskStore.toggle")
@MainActor
struct ToggleTests {
  @Test("starting a task stamps startedAt with now")
  func start() {
    let (store, clock, _) = makeStore(tasks: [TrackedTask(title: "A")])
    store.toggle(store.tasks[0].id)

    #expect(store.tasks[0].running == true)
    #expect(store.tasks[0].startedAt == clock.now)
  }

  @Test("stopping banks the elapsed time and clears startedAt")
  func stopBanks() {
    let (store, clock, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 5)])
    store.toggle(store.tasks[0].id)
    clock.advance(ms: 10_000)
    store.toggle(store.tasks[0].id)

    #expect(store.tasks[0].running == false)
    #expect(store.tasks[0].seconds == 15)
    #expect(store.tasks[0].startedAt == 0)
  }

  @Test("several tasks can run at once")
  func multipleRunning() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A"), TrackedTask(title: "B")])
    store.toggle(store.tasks[0].id)
    store.toggle(store.tasks[1].id)

    #expect(store.tasks.allSatisfy { $0.running })
    #expect(store.anyRunning)
  }
}

@Suite("TaskStore.reset")
@MainActor
struct ResetTests {
  @Test("resetting a running task zeroes it but keeps it running from now")
  func resetWhileRunning() {
    let (store, clock, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 60)])
    store.toggle(store.tasks[0].id)
    clock.advance(ms: 30_000)
    store.reset(store.tasks[0].id)

    #expect(store.tasks[0].seconds == 0)
    #expect(store.tasks[0].running == true)
    #expect(store.tasks[0].startedAt == clock.now)
  }

  @Test("resetting a stopped task just zeroes it")
  func resetWhileStopped() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 60)])
    store.reset(store.tasks[0].id)

    #expect(store.tasks[0].seconds == 0)
    #expect(store.tasks[0].running == false)
    #expect(store.tasks[0].startedAt == 0)
  }

  @Test("resetAll zeroes every task and keeps running ones running")
  func resetAll() {
    let (store, clock, _) = makeStore(tasks: [
      TrackedTask(title: "A", seconds: 60),
      TrackedTask(title: "B", seconds: 30),
    ])
    store.toggle(store.tasks[0].id)
    clock.advance(ms: 5_000)
    store.resetAll()

    #expect(store.tasks.allSatisfy { $0.seconds == 0 })
    #expect(store.tasks[0].running == true)
    #expect(store.tasks[0].startedAt == clock.now)
    #expect(store.tasks[1].running == false)
  }
}

@Suite("TaskStore.delete")
@MainActor
struct DeleteTests {
  @Test("deleting selects the following task")
  func selectsNeighbor() {
    let (store, _, _) = makeStore(tasks: [
      TrackedTask(title: "A"), TrackedTask(title: "B"), TrackedTask(title: "C"),
    ])
    let second = store.tasks[1].id
    store.selectedID = second
    store.delete(second)

    #expect(store.tasks.map(\.title) == ["A", "C"])
    #expect(store.selectedID == store.tasks[1].id)  // "C" took the same index
  }

  @Test("deleting the last task selects the previous one")
  func selectsPreviousAtEnd() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A"), TrackedTask(title: "B")])
    let last = store.tasks[1].id
    store.selectedID = last
    store.delete(last)

    #expect(store.tasks.map(\.title) == ["A"])
    #expect(store.selectedID == store.tasks[0].id)
  }

  @Test("deleting the only task clears the selection")
  func clearsSelection() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A")])
    store.delete(store.tasks[0].id)

    #expect(store.tasks.isEmpty)
    #expect(store.selectedID == nil)
  }
}

@Suite("TaskStore.commitEdit")
@MainActor
struct CommitEditTests {
  @Test("beginning an edit pauses a running task at its current elapsed time")
  func pausesRunningTask() {
    let (store, clock, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 5)])
    let id = store.tasks[0].id
    store.toggle(id)
    clock.advance(ms: 10_000)

    store.beginEdit(id)

    #expect(store.tasks[0].seconds == 15)
    #expect(store.tasks[0].running == false)
    #expect(store.tasks[0].startedAt == 0)
    #expect(store.editingID == id)
    #expect(elapsedSeconds(store.tasks[0], nowMs: clock.now) == 15)
  }

  @Test("cancelling an edit resumes only the task that was running")
  func cancelResumesPausedTask() {
    let (store, clock, _) = makeStore(tasks: [
      TrackedTask(title: "A", seconds: 5),
      TrackedTask(title: "B", seconds: 20),
    ])
    let firstID = store.tasks[0].id
    let secondID = store.tasks[1].id
    store.toggle(firstID)
    store.toggle(secondID)
    clock.advance(ms: 10_000)

    store.beginEdit(firstID)
    #expect(store.tasks[0].running == false)
    #expect(store.tasks[1].running == true)
    #expect(elapsedSeconds(store.tasks[0], nowMs: clock.now) == 15)
    #expect(elapsedSeconds(store.tasks[1], nowMs: clock.now) == 30)

    clock.advance(ms: 4_000)
    store.cancelEdit()

    #expect(store.tasks[0].running == true)
    #expect(store.tasks[0].seconds == 15)
    #expect(store.tasks[0].startedAt == clock.now)
    #expect(elapsedSeconds(store.tasks[1], nowMs: clock.now) == 34)
  }

  @Test("committing an edit resumes the paused task from the entered duration")
  func commitResumesPausedTask() {
    let (store, clock, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 5)])
    let id = store.tasks[0].id
    store.toggle(id)
    clock.advance(ms: 10_000)

    store.beginEdit(id)
    store.commitEdit(id, title: "Updated", durationText: "1:00")

    #expect(store.tasks[0].title == "Updated")
    #expect(store.tasks[0].seconds == 60)
    #expect(store.tasks[0].running == true)
    #expect(store.tasks[0].startedAt == clock.now)
    #expect(store.editingID == nil)
  }

  @Test("beginning an edit on a stopped task preserves its time")
  func preservesStoppedTask() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 42)])
    let id = store.tasks[0].id

    store.beginEdit(id)

    #expect(store.tasks[0].seconds == 42)
    #expect(store.tasks[0].running == false)
    #expect(store.editingID == id)
  }

  @Test("beginning an edit seeds the drafts from the task's current title and time")
  func seedsDrafts() {
    let (store, clock, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 5)])
    let id = store.tasks[0].id
    store.toggle(id)
    clock.advance(ms: 10_000)

    store.beginEdit(id)

    #expect(store.draftTitle == "A")
    #expect(store.draftDuration == "00:00:15")
  }

  @Test("re-editing after a reset shows the reset time, not the previous edit's")
  func reseedsDraftsOnEveryEdit() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "3S Groom", seconds: 3102)])
    let id = store.tasks[0].id

    store.beginEdit(id)
    #expect(store.draftDuration == "00:51:42")
    store.cancelEdit()
    store.reset(id)

    store.beginEdit(id)
    #expect(store.draftDuration == "00:00:00")
  }

  @Test("switching the editor to another task seeds that task's values")
  func switchingTasksReseedsDrafts() {
    let (store, _, _) = makeStore(tasks: [
      TrackedTask(title: "SG-2784", seconds: 10_991),
      TrackedTask(title: "SG-2783", seconds: 1),
    ])

    store.beginEdit(store.tasks[0].id)
    store.beginEdit(store.tasks[1].id)

    #expect(store.draftTitle == "SG-2783")
    #expect(store.draftDuration == "00:00:01")
  }

  @Test("an unparseable duration keeps the stored time but still applies the title")
  func unparseableKeepsTime() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A", seconds: 42)])
    store.commitEdit(store.tasks[0].id, title: "Renamed", durationText: "nonsense")

    #expect(store.tasks[0].seconds == 42)
    #expect(store.tasks[0].title == "Renamed")
  }

  @Test("an empty title becomes Empty")
  func emptyTitle() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A")])
    store.commitEdit(store.tasks[0].id, title: "   ", durationText: "30")

    #expect(store.tasks[0].title == "Empty")
    #expect(store.tasks[0].seconds == 30)
  }

  @Test("committing closes the editor")
  func closesEditor() {
    let (store, _, _) = makeStore()
    store.add()
    store.commitEdit(store.tasks[0].id, title: "A", durationText: "5")

    #expect(store.editingID == nil)
  }
}

@Suite("TaskStore.moveSelection")
@MainActor
struct MoveSelectionTests {
  @Test("moving down from nothing selects the first task")
  func downFromNothing() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A"), TrackedTask(title: "B")])
    store.moveSelection(by: 1)
    #expect(store.selectedID == store.tasks[0].id)
  }

  @Test("selection moves and stops at the ends rather than wrapping")
  func clampsAtEnds() {
    let (store, _, _) = makeStore(tasks: [TrackedTask(title: "A"), TrackedTask(title: "B")])
    store.selectedID = store.tasks[0].id

    store.moveSelection(by: 1)
    #expect(store.selectedID == store.tasks[1].id)

    store.moveSelection(by: 1)
    #expect(store.selectedID == store.tasks[1].id)

    store.moveSelection(by: -1)
    #expect(store.selectedID == store.tasks[0].id)

    store.moveSelection(by: -1)
    #expect(store.selectedID == store.tasks[0].id)
  }

  @Test("moving with no tasks does nothing")
  func noTasks() {
    let (store, _, _) = makeStore()
    store.moveSelection(by: 1)
    #expect(store.selectedID == nil)
  }
}

@Suite("TaskStore persistence round-trip")
@MainActor
struct RoundTripTests {
  @Test("a running timer continues across a save and reload")
  func continuesAcrossReload() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("TimeTrackerStore-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("tasks.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let clock = FakeClock(1_000_000)
    let persistence = JSONFilePersistence(url: url)
    let store = TaskStore(persistence: persistence, now: { clock.now })
    store.add()
    store.commitEdit(store.tasks[0].id, title: "Write", durationText: "10")
    store.add()
    store.toggle(store.tasks[1].id)

    // A fresh store reading the same file, 30 seconds later.
    clock.advance(ms: 30_000)
    let reloaded = TaskStore(persistence: JSONFilePersistence(url: url), now: { clock.now })

    #expect(reloaded.tasks == store.tasks)
    #expect(reloaded.tasks[0].seconds == 10)
    #expect(elapsedSeconds(reloaded.tasks[1], nowMs: clock.now) == 30)
    #expect(reloaded.totalSecondsNow == 40)
  }
}
