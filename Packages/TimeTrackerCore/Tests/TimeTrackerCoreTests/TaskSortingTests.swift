import Foundation
import Testing
@testable import TimeTrackerCore

@MainActor
private func makeStore(tasks: [TrackedTask] = []) -> (TaskStore, InMemoryPersistence) {
  let persistence = InMemoryPersistence(tasks: tasks)
  let store = TaskStore(persistence: persistence, now: { 1_000_000 })
  return (store, persistence)
}

@MainActor
private func titles(_ store: TaskStore) -> [String] {
  store.tasks.map(\.title)
}

@Suite("TaskStore sorting")
@MainActor
struct TaskSortingTests {
  @Test("loading unsorted data orders tasks by title")
  func loadSorts() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Cherry"),
      TrackedTask(title: "apple"),
      TrackedTask(title: "Banana"),
    ])
    #expect(titles(store) == ["apple", "Banana", "Cherry"])
  }

  @Test("ordering is case-insensitive and numeric-aware")
  func caseInsensitiveNumeric() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Task 10"),
      TrackedTask(title: "task 2"),
      TrackedTask(title: "Task 1"),
    ])
    #expect(titles(store) == ["Task 1", "task 2", "Task 10"])
  }

  @Test("equal titles are ordered by id so the order is deterministic")
  func stableTiebreak() {
    let first = TrackedTask(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Same")
    let second = TrackedTask(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Same")
    let (store, _) = makeStore(tasks: [second, first])
    #expect(store.tasks.map(\.id) == [first.id, second.id])
  }

  @Test("add places the Empty task in sorted position with editor and selection on it")
  func addSorted() {
    let (store, persistence) = makeStore(tasks: [TrackedTask(title: "Alpha"), TrackedTask(title: "Zulu")])
    store.add()

    #expect(titles(store) == ["Alpha", "Empty", "Zulu"])
    let added = store.tasks[1]
    #expect(store.selectedID == added.id)
    #expect(store.editingID == added.id)
    #expect(store.draftTitle == "Empty")
    #expect(persistence.load().map(\.title) == ["Alpha", "Empty", "Zulu"])
  }

  @Test("renaming on commit re-sorts and selection follows the task")
  func commitResorts() {
    let (store, persistence) = makeStore(tasks: [
      TrackedTask(title: "Alpha"),
      TrackedTask(title: "Beta"),
      TrackedTask(title: "Gamma"),
    ])
    let id = store.tasks[0].id
    store.beginEdit(id)
    store.commitEdit(id, title: "Zeta", durationText: "00:00:00")

    #expect(titles(store) == ["Beta", "Gamma", "Zeta"])
    #expect(store.selectedID == id)
    #expect(store.tasks[2].id == id)
    #expect(persistence.load().map(\.title) == ["Beta", "Gamma", "Zeta"])
  }

  @Test("editing drafts does not re-sort until commit")
  func draftsDoNotResort() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "Alpha"), TrackedTask(title: "Beta")])
    let id = store.tasks[0].id
    store.beginEdit(id)
    store.draftTitle = "Zeta"

    #expect(titles(store) == ["Alpha", "Beta"])
  }

  @Test("moveSelection walks the sorted order")
  func moveSelectionSorted() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "C"), TrackedTask(title: "A"), TrackedTask(title: "B")])
    store.moveSelection(by: 1)
    #expect(store.selectedID == store.tasks[0].id)
    #expect(store.tasks[0].title == "A")
    store.moveSelection(by: 1)
    #expect(store.tasks.first { $0.id == store.selectedID }?.title == "B")
  }

  @Test("delete selects the next task in sorted order")
  func deleteNeighborSorted() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "C"), TrackedTask(title: "A"), TrackedTask(title: "B")])
    let a = store.tasks[0].id
    store.selectedID = a
    store.delete(a)
    #expect(store.tasks.first { $0.id == store.selectedID }?.title == "B")
  }
}
