import Foundation
import Observation

/// A shared one-second heartbeat driving every elapsed-time readout.
///
/// One timer for the whole app rather than one per row: the views read
/// `clock.now` and recompute their own elapsed seconds, so they always agree.
///
/// The timer runs only when it is needed — something is running, or the
/// popover is open — because an idle menu bar app should use no CPU at all.
@MainActor
@Observable
public final class Clock {
  /// Current time in epoch milliseconds. Views observe this.
  public private(set) var now: Int = Int(Date().timeIntervalSince1970 * 1000)

  @ObservationIgnored private var timer: Timer?

  public init() {}

  public var isRunning: Bool { timer != nil }

  public func start() {
    guard timer == nil else { return }
    tick()

    let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
      // In Swift 6 a Timer's closure is @Sendable, but Timer always fires on
      // the run loop that scheduled it — the main one here. `assumeIsolated`
      // tells the compiler what is already true instead of hopping actors.
      MainActor.assumeIsolated {
        self.tick()
      }
    }
    // Tolerance lets macOS coalesce our wakeup with others, saving power.
    timer.tolerance = 0.1
    // .common keeps it ticking while menus/tracking loops are active.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// Refreshes `now` without waiting for the next tick — used when the popover
  /// opens so the first frame is never up to a second stale.
  public func tick() {
    now = Int(Date().timeIntervalSince1970 * 1000)
  }
}
