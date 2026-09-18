import Testing
@testable import TimeTrackerCore

@Suite("elapsedSeconds")
struct ElapsedSecondsTests {
  @Test("a stopped task reports its banked seconds")
  func stopped() {
    let task = TrackedTask(title: "Read", seconds: 120, running: false, startedAt: 0)
    #expect(elapsedSeconds(task, nowMs: 10_000_000) == 120)
  }

  @Test("a running task adds whole seconds since startedAt")
  func running() {
    let task = TrackedTask(title: "Read", seconds: 120, running: true, startedAt: 1_000_000)
    // 4.5s elapsed floors to 4.
    #expect(elapsedSeconds(task, nowMs: 1_004_500) == 124)
  }

  @Test("a startedAt in the future contributes nothing")
  func futureStart() {
    let task = TrackedTask(title: "Read", seconds: 120, running: true, startedAt: 2_000_000)
    #expect(elapsedSeconds(task, nowMs: 1_000_000) == 120)
  }

  @Test("running with a non-positive startedAt contributes nothing")
  func zeroStart() {
    let task = TrackedTask(title: "Read", seconds: 120, running: true, startedAt: 0)
    #expect(elapsedSeconds(task, nowMs: 1_000_000) == 120)
  }
}

@Suite("totalSeconds")
struct TotalSecondsTests {
  @Test("sums every task, running and stopped alike")
  func sumsAll() {
    let tasks = [
      TrackedTask(title: "A", seconds: 100, running: false, startedAt: 0),
      TrackedTask(title: "B", seconds: 50, running: true, startedAt: 1_000_000),
    ]
    #expect(totalSeconds(tasks, nowMs: 1_010_000) == 160)
  }

  @Test("no tasks totals zero")
  func empty() {
    #expect(totalSeconds([], nowMs: 1_000_000) == 0)
  }
}

@Suite("TrackedTask.normalized")
struct NormalizedTests {
  @Test("running with no startedAt normalizes to stopped")
  func runningWithoutStart() {
    let task = TrackedTask(title: "A", seconds: 10, running: true, startedAt: 0).normalized()
    #expect(task.running == false)
    #expect(task.startedAt == 0)
    #expect(task.seconds == 10)
  }

  @Test("a blank title becomes Empty")
  func blankTitle() {
    #expect(TrackedTask(title: "   ", seconds: 0, running: false, startedAt: 0).normalized().title == "Empty")
  }

  @Test("a legitimately running task is left alone")
  func leavesRunningAlone() {
    let task = TrackedTask(title: "A", seconds: 10, running: true, startedAt: 500).normalized()
    #expect(task.running == true)
    #expect(task.startedAt == 500)
  }

  @Test("negative banked seconds clamp to zero")
  func negativeSeconds() {
    #expect(TrackedTask(title: "A", seconds: -5, running: false, startedAt: 0).normalized().seconds == 0)
  }
}
