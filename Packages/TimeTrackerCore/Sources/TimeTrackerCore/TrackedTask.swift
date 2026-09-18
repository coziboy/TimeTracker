import Foundation

/// One tracked task.
///
/// Named `TrackedTask` rather than `Task` so it never shadows Swift
/// Concurrency's `Task` type inside this module or the app.
///
/// Time is stored in two halves so a running timer survives quitting the app:
/// - `seconds` is time already *banked* by previous start/stop cycles.
/// - `startedAt` is when the current run began (epoch milliseconds, `0` when stopped).
///
/// Displayed time is `seconds + (now - startedAt)`, so relaunching after a day
/// with a timer left running shows the full day.
public struct TrackedTask: Codable, Sendable, Identifiable, Equatable {
  public var id: UUID
  public var title: String
  /// Banked seconds from completed runs.
  public var seconds: Int
  public var running: Bool
  /// Epoch milliseconds when the current run started; `0` when stopped.
  public var startedAt: Int

  public init(
    id: UUID = UUID(),
    title: String,
    seconds: Int = 0,
    running: Bool = false,
    startedAt: Int = 0
  ) {
    self.id = id
    self.title = title
    self.seconds = seconds
    self.running = running
    self.startedAt = startedAt
  }

  /// Repairs states that should not exist, applied to everything read from disk.
  ///
  /// A task marked running with no `startedAt` (a crash mid-write, or a
  /// hand-edited file) would otherwise count from 1970, so it becomes stopped.
  public func normalized() -> TrackedTask {
    var copy = self
    if copy.running && copy.startedAt <= 0 {
      copy.running = false
      copy.startedAt = 0
    }
    if !copy.running {
      copy.startedAt = 0
    }
    if copy.seconds < 0 {
      copy.seconds = 0
    }
    if copy.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      copy.title = "Empty"
    }
    return copy
  }
}
