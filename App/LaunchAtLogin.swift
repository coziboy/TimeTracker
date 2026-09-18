import Observation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` so the gear menu can show and flip
/// the login-item state without knowing about ServiceManagement.
@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status: SMAppService.Status = .notFound

  init() {
    refresh()
  }

  var isEnabled: Bool { status == .enabled }

  /// `.notFound` means macOS has no registration record for this bundle —
  /// the normal case for a Debug build running out of DerivedData. The toggle
  /// is disabled rather than silently failing.
  var isAvailable: Bool { status != .notFound }

  /// Set when the user has to finish the job in System Settings, which macOS
  /// requires after certain denials.
  var requiresApproval: Bool { status == .requiresApproval }

  var explanation: String? {
    switch status {
    case .notFound:
      "Unavailable until the app is moved to /Applications"
    case .requiresApproval:
      "Approve TimeTracker in System Settings › Login Items"
    default:
      nil
    }
  }

  func refresh() {
    status = SMAppService.mainApp.status
  }

  func toggle() {
    do {
      if isEnabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      // A failure here is almost always `.requiresApproval` in disguise;
      // refreshing surfaces the real status and the UI explains the next step.
    }
    refresh()
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
