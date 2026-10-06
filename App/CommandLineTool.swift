import AppKit

/// Links the `timetracker` CLI bundled in the app into `~/.local/bin`, the
/// same place `install.sh` puts it, so it updates with every reinstall.
///
/// The binary lives in `Contents/Helpers/`, not `Contents/MacOS/`: the default
/// case-insensitive volume cannot hold `timetracker` beside `TimeTracker`.
@MainActor
enum CommandLineTool {
  static var bundledURL: URL {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/timetracker")
  }

  static var linkURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local/bin/timetracker")
  }

  /// True when the link exists and points at this copy of the app.
  static var isInstalled: Bool {
    let target = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
    return target == bundledURL.path
  }

  enum InstallError: LocalizedError {
    case missingBinary
    case occupied(String)

    var errorDescription: String? {
      switch self {
      case .missingBinary:
        "This copy of TimeTracker has no bundled command line tool."
      case .occupied(let path):
        "\(path) already exists and is not a link. Move it away and try again."
      }
    }
  }

  static func install() throws {
    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: bundledURL.path) else {
      throw InstallError.missingBinary
    }
    try fileManager.createDirectory(
      at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    // Replace an old link (say, to a build folder), but never a real file —
    // that is something the user put there.
    if (try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path)) != nil {
      try fileManager.removeItem(at: linkURL)
    } else if fileManager.fileExists(atPath: linkURL.path) {
      throw InstallError.occupied(linkURL.path)
    }
    try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: bundledURL)
  }

  /// Installs and reports the outcome in an alert.
  static func installShowingResult() {
    let alert = NSAlert()
    do {
      try install()
      alert.messageText = "Command line tool installed"
      alert.informativeText = """
        \(linkURL.path) now runs TimeTracker from the terminal. \
        Try: timetracker help

        If the command is not found, add ~/.local/bin to your PATH.
        For tab completion in zsh, add to ~/.zshrc:
        eval "$(timetracker completion zsh)"
        """
    } catch {
      alert.alertStyle = .warning
      alert.messageText = "Could not install the command line tool"
      alert.informativeText = error.localizedDescription
    }
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
}
