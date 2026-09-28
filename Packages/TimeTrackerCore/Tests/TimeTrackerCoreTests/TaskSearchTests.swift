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
private func visibleTitles(_ store: TaskStore) -> [String] {
  store.visibleTasks.map(\.title)
}

@MainActor
private func id(of title: String, in store: TaskStore) -> UUID {
  store.tasks.first(where: { $0.title == title })!.id
}

@Suite("TaskStore search")
@MainActor
struct TaskSearchTests {
  @Test("an empty or whitespace-only query shows every task")
  func emptyQueryShowsAll() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "Beta"), TrackedTask(title: "Alpha")])
    #expect(visibleTitles(store) == ["Alpha", "Beta"])

    store.searchQuery = "   "
    #expect(visibleTitles(store) == ["Alpha", "Beta"])
  }

  @Test("matching is case- and diacritic-insensitive and ignores surrounding whitespace")
  func caseAndDiacriticInsensitive() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Café meeting"),
      TrackedTask(title: "CAFETERIA"),
      TrackedTask(title: "Email"),
    ])
    store.searchQuery = " cafe "
    #expect(visibleTitles(store) == ["Café meeting", "CAFETERIA"])

    store.searchQuery = "MAIL"
    #expect(visibleTitles(store) == ["Email"])

    store.searchQuery = "nothing"
    #expect(store.visibleTasks.isEmpty)
  }

  @Test("results keep the sorted order and do not change tasks")
  func resultsStaySorted() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Task 10"),
      TrackedTask(title: "Other"),
      TrackedTask(title: "task 2"),
      TrackedTask(title: "Task 1"),
    ])
    store.searchQuery = "task"
    #expect(visibleTitles(store) == ["Task 1", "task 2", "Task 10"])
    #expect(store.tasks.map(\.title) == ["Other", "Task 1", "task 2", "Task 10"])
  }

  @Test("moveSelection navigates only the visible tasks")
  func moveSelectionWithinVisible() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Apple"),
      TrackedTask(title: "Banana"),
      TrackedTask(title: "Apricot"),
      TrackedTask(title: "Cherry"),
    ])
    store.searchQuery = "ap"
    #expect(store.selectedID == id(of: "Apple", in: store))

    store.moveSelection(by: 1)
    #expect(store.selectedID == id(of: "Apricot", in: store))
    store.moveSelection(by: 1)
    #expect(store.selectedID == id(of: "Apricot", in: store))
    store.moveSelection(by: -5)
    #expect(store.selectedID == id(of: "Apple", in: store))
  }

  @Test("a query that hides the selection moves it to the first visible task, or nil")
  func selectionRetargets() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Alpha"),
      TrackedTask(title: "Beta"),
      TrackedTask(title: "Bravo"),
    ])
    store.selectedID = id(of: "Alpha", in: store)

    store.searchQuery = "b"
    #expect(store.selectedID == id(of: "Beta", in: store))

    // A selection that is still visible stays put.
    store.selectedID = id(of: "Bravo", in: store)
    store.searchQuery = "br"
    #expect(store.selectedID == id(of: "Bravo", in: store))

    store.searchQuery = "zzz"
    #expect(store.selectedID == nil)
  }

  @Test("a query that hides the task being edited cancels the edit")
  func hiddenEditorCancels() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "Alpha"), TrackedTask(title: "Beta")])
    store.beginEdit(id(of: "Alpha", in: store))

    store.searchQuery = "beta"
    #expect(store.editingID == nil)
    #expect(store.selectedID == id(of: "Beta", in: store))
  }

  @Test("add clears the search so the new task and its editor are visible")
  func addClearsQuery() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "Alpha"), TrackedTask(title: "Zulu")])
    store.searchQuery = "zulu"

    store.add()

    #expect(store.searchQuery == "")
    #expect(visibleTitles(store) == ["Alpha", "Empty", "Zulu"])
    let added = id(of: "Empty", in: store)
    #expect(store.selectedID == added)
    #expect(store.editingID == added)
  }

  @Test("delete selects a visible neighbor, not a hidden one")
  func deletePicksVisibleNeighbor() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Apple"),
      TrackedTask(title: "Apricot"),
      TrackedTask(title: "Banana"),
    ])
    store.searchQuery = "ap"
    store.selectedID = id(of: "Apricot", in: store)

    // Apricot is the last visible row; Banana follows it in `tasks` but is hidden.
    store.delete(id(of: "Apricot", in: store))
    #expect(store.selectedID == id(of: "Apple", in: store))

    store.delete(id(of: "Apple", in: store))
    #expect(store.selectedID == nil)
    #expect(store.tasks.map(\.title) == ["Banana"])
  }

  @Test("a rename that leaves the search results moves the selection")
  func commitRetargetsHiddenSelection() {
    let (store, _) = makeStore(tasks: [TrackedTask(title: "Apple"), TrackedTask(title: "Apricot")])
    store.searchQuery = "ap"
    let apple = id(of: "Apple", in: store)
    store.beginEdit(apple)

    store.commitEdit(apple, title: "Pear", durationText: "0:00")
    #expect(store.selectedID == id(of: "Apricot", in: store))
  }

  @Test("the total covers every task, not just the visible ones")
  func totalIgnoresSearch() {
    let (store, _) = makeStore(tasks: [
      TrackedTask(title: "Alpha", seconds: 60),
      TrackedTask(title: "Beta", seconds: 30),
    ])
    store.searchQuery = "alpha"
    #expect(store.totalSecondsNow == 90)
  }
}
