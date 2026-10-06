import Foundation
import OSLog

/// Where the task list lives. Abstracted so tests can run against memory
/// instead of the real Application Support file.
public protocol TaskPersisting: Sendable {
  func load() -> [TrackedTask]
  func save(_ tasks: [TrackedTask])
  /// The stored tasks, or `nil` when the store exists but cannot be read.
  func loadIfReadable() -> [TrackedTask]?
}

extension TaskPersisting {
  /// Stores that cannot be unreadable simply load.
  public func loadIfReadable() -> [TrackedTask]? { load() }
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
    // Deliberately leave a bad file alone: starting empty is recoverable,
    // overwriting the user's only copy is not. The next save replaces it.
    loadIfReadable() ?? []
  }

  /// Like `load()`, but tells a missing file (`[]`, a first launch) apart
  /// from one that exists and cannot be decoded (`nil`).
  ///
  /// The CLI and the app's live reload use this so that neither ever acts on
  /// — and then writes over — a file it could not read.
  public func loadIfReadable() -> [TrackedTask]? {
    guard let data = try? Data(contentsOf: url) else {
      // No file yet — a first launch, not an error.
      return []
    }
    do {
      // Every task from disk goes through `normalized()` so a corrupt or
      // hand-edited entry cannot put the UI into an impossible state.
      return try JSONDecoder().decode([TrackedTask].self, from: data).map { $0.normalized() }
    } catch {
      logger.error("Could not decode \(url.path, privacy: .public): \(error.localizedDescription)")
      return nil
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
