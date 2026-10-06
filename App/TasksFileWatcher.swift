import Foundation

/// Calls back when anything in the data directory changes — chiefly the
/// `timetracker` CLI rewriting `tasks.json`.
///
/// It watches the *directory*, not the file: every save is atomic, which
/// writes a new file and renames it over the old one, so a watch on the old
/// file's descriptor would go quiet after the first save. The app's own saves
/// fire it too; `TaskStore.reload()` finds nothing new and does nothing.
///
/// It lives as long as the app, so it never tears the source down.
@MainActor
final class TasksFileWatcher {
  private var source: DispatchSourceFileSystemObject?
  private var pending: DispatchWorkItem?
  private let onChange: @MainActor () -> Void

  init(directory: URL, onChange: @escaping @MainActor () -> Void) {
    self.onChange = onChange
    // The directory may not exist before the first save, and there is
    // nothing to watch until it does.
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let descriptor = open(directory.path, O_EVTONLY)
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: .write, queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.scheduleChange() }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    self.source = source
  }

  /// One atomic save is several directory events (temp file created, then
  /// renamed), so wait for them to settle and report once.
  private func scheduleChange() {
    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.onChange() }
    }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
  }
}
