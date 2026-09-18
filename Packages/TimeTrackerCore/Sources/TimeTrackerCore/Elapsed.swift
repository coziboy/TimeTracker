import Foundation

/// Seconds to display for one task at instant `nowMs` (epoch milliseconds).
///
/// A running task adds the whole seconds since `startedAt`. A clock that has
/// moved backwards (or a bad `startedAt`) adds nothing rather than going negative.
public func elapsedSeconds(_ task: TrackedTask, nowMs: Int) -> Int {
  let banked = max(0, task.seconds)
  guard task.running, task.startedAt > 0, nowMs > task.startedAt else {
    return banked
  }
  return banked + (nowMs - task.startedAt) / 1000
}

/// Combined seconds across every task — the number shown in the menu bar.
public func totalSeconds(_ tasks: [TrackedTask], nowMs: Int) -> Int {
  tasks.reduce(0) { $0 + elapsedSeconds($1, nowMs: nowMs) }
}
