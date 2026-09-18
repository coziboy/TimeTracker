import Observation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` so the gear menu can show and flip
/// the login-item state without knowing about ServiceManagement.
@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status: SMAppService.Status = .notFound

  /// Set when a register/unregister attempt actually failed, so the menu can
  /// say so instead of silently doing nothing.
  private(set) var lastErrorDescription: String?

  init() {
    refresh()
  }

  var isEnabled: Bool { status == .enabled }

  /// Whether the toggle can be operated.
  ///
  /// Note `.notFound` is *not* a blocker: it is simply what macOS reports for
  /// a bundle it holds no registration record for, which is every app that has
  /// never been registered. Calling `register()` from that state works and
  /// moves it to `.enabled`. Only a pending approval takes the user elsewhere.
  var isAvailable: Bool { true }

  /// Set when the user has to finish the job in System Settings, which macOS
  /// requires after certain denials.
  var requiresApproval: Bool { status == .requiresApproval }

  var explanation: String? {
    if let lastErrorDescription {
      return lastErrorDescription
    }
    if status == .requiresApproval {
      return "Approve TimeTracker in System Settings › Login Items"
    }
    return nil
  }

  func refresh() {
    status = SMAppService.mainApp.status
  }

  func toggle() {
    lastErrorDescription = nil
    do {
      // `.enabled` is the only state that means "registered"; everything else
      // (including .notFound) should attempt to register.
      if isEnabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      // Surface the failure rather than swallowing it — a silently dead
      // toggle is the worst outcome for the user.
      lastErrorDescription = error.localizedDescription
    }
    refresh()
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
