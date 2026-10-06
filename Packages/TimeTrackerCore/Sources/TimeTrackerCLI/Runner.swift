import Foundation
import TimeTrackerCore

/// What a command printed and how the process should exit.
public struct CLIResult: Equatable, Sendable {
  public var output: String = ""
  public var error: String = ""
  public var exitCode: Int32 = 0

  static func success(_ output: String) -> CLIResult { CLIResult(output: output) }
  static func failure(_ error: String, code: Int32 = 1) -> CLIResult {
    CLIResult(error: error, exitCode: code)
  }
}

/// Parses and runs one invocation against the data file it names.
///
/// `environment` supplies `TIMETRACKER_DATA`; `--file` beats it, and the app's
/// own `tasks.json` is the default.
@MainActor
public func runCLI(
  arguments: [String],
  environment: [String: String] = ProcessInfo.processInfo.environment
) -> CLIResult {
  let invocation: Invocation
  do {
    invocation = try parseInvocation(arguments)
  } catch {
    return .failure("timetracker: \(error)\nRun 'timetracker help' for usage.", code: 2)
  }

  let url =
    (invocation.dataFile ?? environment["TIMETRACKER_DATA"])
    .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    ?? JSONFilePersistence.defaultURL
  return execute(invocation.command, persistence: JSONFilePersistence(url: url), dataPath: url.path)
}

/// Runs a parsed command. Split from `runCLI` so tests can use in-memory
/// persistence and a fixed clock.
@MainActor
public func execute(
  _ command: Command,
  persistence: any TaskPersisting,
  dataPath: String = "the task store",
  now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }
) -> CLIResult {
  // Commands that never touch the data run even when it is unreadable.
  switch command {
  case .help:
    return .success(helpText)
  case .completion(let shell):
    return .success(completionScript(for: shell))
  default:
    break
  }

  // TaskStore treats an unreadable file as empty, which is right for the app
  // at launch but would let a CLI write replace the user's only copy. Refuse.
  guard persistence.loadIfReadable() != nil else {
    if case .completeTasks = command { return .success("") }
    return .failure(
      "timetracker: cannot read \(dataPath); fix or move it first. Nothing was changed.")
  }
  let store = TaskStore(persistence: persistence, now: now)

  func time(_ task: TrackedTask) -> String {
    formatDuration(store.elapsed(task, at: now()))
  }
  func current(_ id: UUID) -> TrackedTask? {
    store.tasks.first { $0.id == id }
  }

  func withTask(_ query: String, _ body: (TrackedTask) -> CLIResult) -> CLIResult {
    switch resolveTask(query, in: store.tasks) {
    case .found(let task):
      return body(task)
    case .notFound:
      return .failure("timetracker: no task matches '\(query)'")
    case .ambiguous(let matches):
      let lines = matches.map { "  \($0.title)  (\($0.id.uuidString))" }
      return .failure(
        (["timetracker: '\(query)' matches several tasks:"] + lines
          + ["Use more of the title, or the id."]).joined(separator: "\n"))
    }
  }

  switch command {
  case .help, .completion:
    preconditionFailure("handled above")

  case .completeTasks:
    return .success(store.tasks.map(\.title).joined(separator: "\n"))

  case .list(let json):
    let nowMs = now()
    if json {
      return .success(
        encodeJSON(
          store.tasks.map {
            TaskJSON(
              id: $0.id.uuidString, title: $0.title,
              seconds: store.elapsed($0, at: nowMs), running: $0.running)
          }))
    }
    guard !store.tasks.isEmpty else {
      return .success("No tasks. Add one with: timetracker add <title>")
    }
    return .success(
      store.tasks.map { "\($0.running ? "●" : "○") \(time($0))  \($0.title)" }
        .joined(separator: "\n"))

  case .status(let json):
    let total = store.totalSecondsNow
    let running = store.tasks.filter(\.running).count
    if json {
      return .success(encodeJSON(StatusJSON(seconds: total, running: running, tasks: store.tasks.count)))
    }
    let suffix = running == 0 ? "nothing running" : "\(running) running"
    return .success("\(formatDuration(total))  \(suffix)")

  case .add(let title, let start):
    let id = store.add(title: title, start: start)
    let task = current(id)!
    return .success(start ? "Added and started \(task.title)" : "Added \(task.title)")

  case .start(let query):
    return withTask(query) { task in
      guard !task.running else { return .success("\(task.title) is already running (\(time(task)))") }
      store.toggle(task.id)
      return .success("Started \(task.title) (\(time(current(task.id)!)))")
    }

  case .stop(let query):
    return withTask(query) { task in
      guard task.running else { return .success("\(task.title) is not running (\(time(task)))") }
      store.toggle(task.id)
      return .success("Stopped \(task.title) at \(time(current(task.id)!))")
    }

  case .toggle(let query):
    return withTask(query) { task in
      store.toggle(task.id)
      let updated = current(task.id)!
      return .success(
        updated.running
          ? "Started \(updated.title) (\(time(updated)))"
          : "Stopped \(updated.title) at \(time(updated))")
    }

  case .reset(let query):
    return withTask(query) { task in
      store.reset(task.id)
      return .success("Reset \(task.title)")
    }

  case .resetAll:
    store.resetAll()
    return .success("Reset \(store.tasks.count) task\(store.tasks.count == 1 ? "" : "s")")

  case .rename(let query, let title):
    return withTask(query) { task in
      store.rename(task.id, to: title)
      return .success("Renamed \(task.title) to \(current(task.id)!.title)")
    }

  case .set(let query, let durationText):
    // Unlike the editor, which keeps the old time on a typo, the CLI says so.
    guard let seconds = parseDuration(durationText) else {
      return .failure(
        "timetracker: cannot read duration '\(durationText)'; try 1:30:00, 90m, 1h30m or 5400",
        code: 2)
    }
    return withTask(query) { task in
      store.setDuration(task.id, seconds: seconds)
      return .success("Set \(task.title) to \(time(current(task.id)!))")
    }

  case .delete(let query):
    return withTask(query) { task in
      store.delete(task.id)
      return .success("Deleted \(task.title) (\(time(task)))")
    }
  }
}

private struct TaskJSON: Encodable {
  let id: String
  let title: String
  /// Elapsed seconds right now, including any current run.
  let seconds: Int
  let running: Bool
}

private struct StatusJSON: Encodable {
  let seconds: Int
  let running: Int
  let tasks: Int
}

private func encodeJSON(_ value: some Encodable) -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  // Encoding these plain structs cannot fail.
  return String(decoding: try! encoder.encode(value), as: UTF8.self)
}
