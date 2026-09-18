import AppKit
import SwiftUI
import TimeTrackerCore

/// The AppKit shell: the menu bar item, the popover that hangs off it, and the
/// keyboard monitor that runs while the popover is open.
///
/// Why AppKit rather than SwiftUI's `MenuBarExtra(.window)`:
/// - its window cannot be made key, so an agent app's popover ignores keystrokes
/// - it cannot be closed programmatically (needed for Esc and after Add)
/// - a live SwiftUI `Text` in the menu bar label pegged the CPU on macOS 26
///
/// So the shell is `NSStatusItem` + `NSPopover`, and everything visible inside
/// is still SwiftUI, hosted by an `NSHostingController`.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
  private let store: TaskStore
  private let clock: Clock
  private let launchAtLogin: LaunchAtLogin
  private let statusItem: NSStatusItem
  private let popover: NSPopover

  /// The local key-down monitor, installed only while the popover is shown.
  private var keyMonitor: Any?

  /// The last title string pushed to the status item, so we can skip redundant
  /// updates — rebuilding the attributed string every second regardless was
  /// what made the SwiftUI version burn CPU.
  private var lastTitle: String?
  private var lastRunning: Bool?

  init(store: TaskStore, clock: Clock, launchAtLogin: LaunchAtLogin) {
    self.store = store
    self.clock = clock
    self.launchAtLogin = launchAtLogin
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.popover = NSPopover()
    super.init()

    configureStatusItem()
    configurePopover()
    updateTitle()
    updateClockPolicy()
    observeClock()
  }

  // MARK: - Setup

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: "timer", accessibilityDescription: "TimeTracker")
    button.imagePosition = .imageLeading
    button.target = self
    button.action = #selector(togglePopover)
  }

  private func configurePopover() {
    popover.behavior = .transient  // clicking outside dismisses it
    popover.animates = false
    popover.delegate = self
    popover.contentViewController = NSHostingController(
      rootView: PopoverView(
        store: store, clock: clock, controller: self, launchAtLogin: launchAtLogin)
    )
  }

  // MARK: - Showing and hiding

  @objc private func togglePopover() {
    // Checking `isShown` is what stops the click that dismisses a transient
    // popover from immediately reopening it.
    if popover.isShown {
      popover.performClose(nil)
    } else {
      show()
    }
  }

  func show() {
    guard let button = statusItem.button else { return }

    // An LSUIElement app is not active by default, and an inactive app's
    // windows cannot become key — which would make every keystroke vanish.
    NSApp.activate()
    clock.tick()  // so the first frame shows current time, not a stale second
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    // Even after activating, the popover window needs an explicit nudge to
    // take key status so the text fields can receive typing.
    popover.contentViewController?.view.window?.makeKey()

    installKeyMonitor()
    updateClockPolicy()
  }

  func close() {
    popover.performClose(nil)
  }

  // NSPopoverDelegate: also fires when the user clicks away, which is why
  // teardown lives here rather than only in `close()`.
  func popoverDidClose(_ notification: Notification) {
    removeKeyMonitor()
    store.cancelEdit()
    updateClockPolicy()
  }

  // MARK: - Clock policy

  /// The heartbeat is needed only when a timer is counting (to update the menu
  /// bar) or the popover is open (to update the rows). Otherwise it stops and
  /// the app costs nothing while idle.
  func updateClockPolicy() {
    if store.anyRunning || popover.isShown {
      clock.start()
    } else {
      clock.stop()
    }
    updateTitle()
  }

  /// Re-runs the menu bar title on every clock tick.
  ///
  /// `withObservationTracking` fires its `onChange` exactly once, before the
  /// value is written, so it has to be re-armed each time — hence the
  /// recursive call. Reading `clock.now` inside `apply` is what registers the
  /// dependency; `updateTitle` then reads the fresh value.
  private func observeClock() {
    withObservationTracking {
      _ = clock.now
    } onChange: { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.updateTitle()
        self.observeClock()
      }
    }
  }

  // MARK: - Menu bar title

  /// Refreshes the status item's text, skipping the work when nothing visible
  /// changed. Called every tick via the clock observation set up below.
  func updateTitle() {
    let title = formatDuration(store.totalSecondsNow)
    let running = store.anyRunning
    guard title != lastTitle || running != lastRunning else { return }
    lastTitle = title
    lastRunning = running

    guard let button = statusItem.button else { return }

    // Keep the item in the menu bar's own colors: template rendering and no
    // tint, so it adapts to light, dark and tinted menu bars like every other
    // status item. Running is signalled by weight, not hue — a timer that is
    // counting is not an error, and a colored menu bar item reads as one.
    button.image?.isTemplate = true
    button.contentTintColor = nil
    button.attributedTitle = NSAttributedString(
      string: " \(title)",
      attributes: [
        // Monospaced digits stop the width jittering as the numbers change.
        .font: NSFont.monospacedDigitSystemFont(
          ofSize: NSFont.systemFontSize, weight: running ? .semibold : .regular),
        .foregroundColor: NSColor.labelColor,
      ]
    )
  }

  // MARK: - Keyboard

  /// A local monitor sees key events before SwiftUI does, so arrow keys work
  /// the instant the popover opens without depending on SwiftUI focus landing
  /// anywhere in particular.
  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    // The closure is not @MainActor-isolated in Swift 6, and NSEvent is not
    // Sendable, so we cannot hop actors with the event in hand. AppKit only
    // ever delivers these on the main thread, so map the event to a plain
    // Sendable command first and assume isolation for the state change.
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let command = KeyCommand(event: event) else { return event }
      // Returning nil swallows the event; returning it passes it on to the
      // text fields (which is what we want while the editor is open).
      let consumed = MainActor.assumeIsolated { self.handle(command) }
      return consumed ? nil : event
    }
  }

  private func removeKeyMonitor() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  /// Returns true when the command was consumed.
  private func handle(_ command: KeyCommand) -> Bool {
    // While the inline editor is open the text fields own the keyboard:
    // only ⌘N and ⌘Q are still ours, everything else must pass through so
    // typing, Tab, Return-to-submit and Esc-to-cancel behave normally.
    let editing = store.editingID != nil
    if editing && !command.worksWhileEditing {
      return false
    }

    switch command {
    case .moveDown:
      store.moveSelection(by: 1)
    case .moveUp:
      store.moveSelection(by: -1)
    case .toggleSelected:
      guard let id = store.selectedID else { return true }
      store.toggle(id)
      updateClockPolicy()
    case .editSelected:
      guard let id = store.selectedID else { return true }
      store.beginEdit(id)
    case .deleteSelected:
      guard let id = store.selectedID else { return true }
      store.delete(id)
      updateClockPolicy()
    case .addTask:
      store.add()
    case .closePopover:
      close()
    case .quit:
      NSApp.terminate(nil)
    }
    return true
  }
}
