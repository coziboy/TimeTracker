import Foundation
import Testing
@testable import TimeTrackerCore

@Suite("JSONFilePersistence")
struct JSONFilePersistenceTests {
  /// A fresh temp file path per test, cleaned up by the caller.
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("TimeTrackerTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("tasks.json")
  }

  @Test("a missing file loads as no tasks")
  func missingFileLoadsEmpty() throws {
    let store = JSONFilePersistence(url: tempURL())
    #expect(store.load().isEmpty)
  }

  @Test("saved tasks load back identically")
  func roundTrip() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let store = JSONFilePersistence(url: url)
    let tasks = [
      TrackedTask(title: "Write", seconds: 90, running: false, startedAt: 0),
      TrackedTask(title: "Read", seconds: 30, running: true, startedAt: 1_700_000_000_000),
    ]
    store.save(tasks)

    #expect(JSONFilePersistence(url: url).load() == tasks)
  }

  @Test("save creates the containing directory")
  func createsDirectory() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    JSONFilePersistence(url: url).save([TrackedTask(title: "A")])
    #expect(FileManager.default.fileExists(atPath: url.path))
  }

  @Test("loaded tasks are normalized")
  func loadNormalizes() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    // Hand-written JSON with an impossible state: running but never started.
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = """
      [{"id":"\(UUID().uuidString)","title":"A","seconds":10,"running":true,"startedAt":0}]
      """
    try json.write(to: url, atomically: true, encoding: .utf8)

    let loaded = JSONFilePersistence(url: url).load()
    #expect(loaded.count == 1)
    #expect(loaded[0].running == false)
  }

  @Test("corrupt JSON loads as no tasks without destroying the file")
  func corruptFileLoadsEmpty() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not json at all".write(to: url, atomically: true, encoding: .utf8)

    #expect(JSONFilePersistence(url: url).load().isEmpty)
    // The unreadable file is left in place for the user to inspect.
    #expect(FileManager.default.fileExists(atPath: url.path))
  }
}

@Suite("InMemoryPersistence")
struct InMemoryPersistenceTests {
  @Test("holds whatever was last saved")
  func holdsTasks() {
    let store = InMemoryPersistence()
    #expect(store.load().isEmpty)

    store.save([TrackedTask(title: "A", seconds: 5)])
    #expect(store.load().count == 1)
    #expect(store.load()[0].title == "A")
  }
}
