import Foundation
import OSLog

/// Where the task list lives. Abstracted so tests can run against memory
/// instead of the real Application Support file.
public protocol TaskPersisting: Sendable {
  func load() -> [TrackedTask]
  func save(_ tasks: [TrackedTask])
}

/// Stores the task list as pretty-printed JSON in a single file.
///
/// The whole list is rewritten on every mutation. That is wasteful in theory
/// and completely irrelevant in practice: the file holds a handful of tasks
/// and a write is well under a millisecond.
public struct JSONFilePersistence: TaskPersisting {
  public let url: URL
  private let logger = Logger(subsystem: "dev.andreas.TimeTracker", category: "persistence")

  /// The default location: `~/Library/Application Support/TimeTracker/tasks.json`.
  public static var defaultURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("TimeTracker", isDirectory: true)
      .appendingPathComponent("tasks.json")
  }

  public init(url: URL = JSONFilePersistence.defaultURL) {
    self.url = url
  }

  public func load() -> [TrackedTask] {
    guard let data = try? Data(contentsOf: url) else {
      // No file yet — a first launch, not an error.
      return []
    }
    do {
      // Every task from disk goes through `normalized()` so a corrupt or
      // hand-edited entry cannot put the UI into an impossible state.
      return try JSONDecoder().decode([TrackedTask].self, from: data).map { $0.normalized() }
    } catch {
      // Deliberately leave the bad file alone: starting empty is recoverable,
      // overwriting the user's only copy is not. The next save replaces it.
      logger.error("Could not decode \(url.path, privacy: .public): \(error.localizedDescription)")
      return []
    }
  }

  public func save(_ tasks: [TrackedTask]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      let data = try encoder.encode(tasks)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      // Atomic: a crash mid-write leaves the previous file intact.
      try data.write(to: url, options: [.atomic])
    } catch {
      logger.error("Could not save \(url.path, privacy: .public): \(error.localizedDescription)")
    }
  }
}

/// Test double. Holds the list in memory, never touching the filesystem.
public final class InMemoryPersistence: TaskPersisting, @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [TrackedTask]

  public init(tasks: [TrackedTask] = []) {
    self.tasks = tasks
  }

  public func load() -> [TrackedTask] {
    lock.withLock { tasks }
  }

  public func save(_ tasks: [TrackedTask]) {
    lock.withLock { self.tasks = tasks }
  }
}
