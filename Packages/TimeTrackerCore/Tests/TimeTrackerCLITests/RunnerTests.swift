import Foundation
import Testing
import TimeTrackerCore
@testable import TimeTrackerCLI

private final class FakeClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int
  init(_ value: Int) { self.value = value }
  var now: Int { lock.withLock { value } }
  func advance(ms: Int) { lock.withLock { value += ms } }
}

/// Runs commands against one in-memory store, the way repeated CLI calls
/// share one file.
@MainActor
private final class Harness {
  let clock = FakeClock(1_000_000)
  let persistence: InMemoryPersistence

  init(_ tasks: [TrackedTask] = []) {
    persistence = InMemoryPersistence(tasks: tasks)
  }

  func run(_ command: Command) -> CLIResult {
    let clock = clock
    return execute(command, persistence: persistence, now: { clock.now })
  }

  var tasks: [TrackedTask] { persistence.load() }
}

@Suite("execute")
@MainActor
struct RunnerTests {
  @Test("list shows state, time and title; empty list says how to add")
  func list() {
    let harness = Harness([
      TrackedTask(title: "Write", seconds: 90),
      TrackedTask(title: "Read", seconds: 5, running: true, startedAt: 1_000_000),
    ])
    harness.clock.advance(ms: 10_000)
    #expect(harness.run(.list(json: false)).output == "● 00:00:15  Read\n○ 00:01:30  Write")
    #expect(Harness().run(.list(json: false)).output.hasPrefix("No tasks."))
  }

  @Test("list --json reports elapsed seconds including the current run")
  func listJSON() throws {
    let task = TrackedTask(title: "Read", seconds: 5, running: true, startedAt: 1_000_000)
    let harness = Harness([task])
    harness.clock.advance(ms: 10_000)

    let decoded = try JSONSerialization.jsonObject(
      with: Data(harness.run(.list(json: true)).output.utf8)) as? [[String: Any]]
    #expect(decoded?.first?["seconds"] as? Int == 15)
    #expect(decoded?.first?["running"] as? Bool == true)
    #expect(decoded?.first?["id"] as? String == task.id.uuidString)
  }

  @Test("status totals every task")
  func status() {
    let harness = Harness([
      TrackedTask(title: "A", seconds: 60),
      TrackedTask(title: "B", seconds: 0, running: true, startedAt: 1_000_000),
    ])
    harness.clock.advance(ms: 30_000)
    #expect(harness.run(.status(json: false)).output == "00:01:30  1 running")
  }

  @Test("add then start then stop banks the time")
  func lifecycle() {
    let harness = Harness()
    #expect(harness.run(.add(title: "Client A", start: false)).output == "Added Client A")
    #expect(harness.run(.start("client")).output == "Started Client A (00:00:00)")
    harness.clock.advance(ms: 42_000)
    #expect(harness.run(.stop("client a")).output == "Stopped Client A at 00:00:42")
    #expect(harness.tasks[0].seconds == 42)
    #expect(harness.tasks[0].running == false)
  }

  @Test("start on a running task, or stop on a stopped one, changes nothing")
  func idempotent() {
    let harness = Harness([
      TrackedTask(title: "A", seconds: 5, running: true, startedAt: 1_000_000)
    ])
    let before = harness.tasks
    #expect(harness.run(.start("A")).output == "A is already running (00:00:05)")
    #expect(harness.tasks == before)

    let stopped = Harness([TrackedTask(title: "B")])
    #expect(stopped.run(.stop("B")).output == "B is not running (00:00:00)")
  }

  @Test("an unknown task fails with status 1")
  func notFound() {
    let result = Harness([TrackedTask(title: "A")]).run(.start("zzz"))
    #expect(result.exitCode == 1)
    #expect(result.error == "timetracker: no task matches 'zzz'")
  }

  @Test("an ambiguous task lists candidates and changes nothing")
  func ambiguous() {
    let harness = Harness([TrackedTask(title: "Client A"), TrackedTask(title: "Client B")])
    let result = harness.run(.delete("client"))
    #expect(result.exitCode == 1)
    #expect(result.error.contains("Client A"))
    #expect(result.error.contains("Client B"))
    #expect(harness.tasks.count == 2)
  }

  @Test("set parses durations and rejects junk with status 2")
  func set() {
    let harness = Harness([TrackedTask(title: "A", seconds: 5)])
    #expect(harness.run(.set("A", duration: "1h30m")).output == "Set A to 01:30:00")
    #expect(harness.tasks[0].seconds == 5400)

    let bad = harness.run(.set("A", duration: "1h2x"))
    #expect(bad.exitCode == 2)
    #expect(harness.tasks[0].seconds == 5400)
  }

  @Test("rename, reset, reset --all and delete apply")
  func mutations() {
    let harness = Harness([TrackedTask(title: "A", seconds: 5), TrackedTask(title: "B", seconds: 7)])
    #expect(harness.run(.rename("A", to: "C")).output == "Renamed A to C")
    #expect(harness.run(.reset("C")).output == "Reset C")
    #expect(harness.tasks.first { $0.title == "C" }?.seconds == 0)
    #expect(harness.run(.resetAll).output == "Reset 2 tasks")
    #expect(harness.run(.delete("B")).output == "Deleted B (00:00:00)")
    #expect(harness.tasks.map(\.title) == ["C"])
  }

  @Test("__complete-tasks prints titles one per line")
  func completeTasks() {
    let harness = Harness([TrackedTask(title: "Client A"), TrackedTask(title: "Admin")])
    #expect(harness.run(.completeTasks).output == "Admin\nClient A")
  }

  @Test("completion prints a script that registers the command")
  func completionScripts() {
    #expect(Harness().run(.completion(.zsh)).output.contains("compdef _timetracker timetracker"))
    #expect(Harness().run(.completion(.bash)).output.contains("complete -F _timetracker timetracker"))
  }
}

@Suite("runCLI with a data file")
@MainActor
struct RunCLIFileTests {
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("TimeTrackerCLITests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("tasks.json")
  }

  @Test("--file beats TIMETRACKER_DATA")
  func fileOverride() throws {
    let flagURL = tempURL()
    let envURL = tempURL()
    defer {
      try? FileManager.default.removeItem(at: flagURL.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: envURL.deletingLastPathComponent())
    }

    _ = runCLI(
      arguments: ["--file", flagURL.path, "add", "X"],
      environment: ["TIMETRACKER_DATA": envURL.path])
    #expect(JSONFilePersistence(url: flagURL).load().map(\.title) == ["X"])
    #expect(!FileManager.default.fileExists(atPath: envURL.path))

    _ = runCLI(arguments: ["add", "Y"], environment: ["TIMETRACKER_DATA": envURL.path])
    #expect(JSONFilePersistence(url: envURL).load().map(\.title) == ["Y"])
  }

  @Test("an unreadable file is refused and left untouched")
  func unreadable() throws {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: url)

    let result = runCLI(arguments: ["--file", url.path, "add", "X"], environment: [:])
    #expect(result.exitCode == 1)
    #expect(result.error.contains("Nothing was changed"))
    #expect(try String(contentsOf: url, encoding: .utf8) == "garbage")
  }

  @Test("usage errors exit 2 with a pointer to help")
  func usage() {
    let result = runCLI(arguments: ["bogus"], environment: [:])
    #expect(result.exitCode == 2)
    #expect(result.error.contains("timetracker help"))
  }
}
