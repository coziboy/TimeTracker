import AppKit
import SwiftUI
import TimeTrackerCore

/// Replaces a row while it is being edited: a title field and a duration field.
///
/// The duration field accepts `HH:MM:SS`, `MM:SS`, `SS`, or unit form like
/// `1h30m`. Anything unparseable leaves the stored time untouched, so a typo
/// cannot silently wipe out tracked hours.
struct InlineEditor: View {
  @State private var title: String
  @State private var duration: String

  /// Which field holds the keyboard. Also used to move focus on Tab.
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case title, duration
  }

  let onCommit: (String, String) -> Void
  let onCancel: () -> Void

  init(
    task: TrackedTask,
    elapsed: Int,
    onCommit: @escaping (String, String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    // Seeded from the *displayed* elapsed time, so editing a running task
    // starts from what the user can actually see on screen.
    _title = State(initialValue: task.title)
    _duration = State(initialValue: formatDuration(elapsed))
    self.onCommit = onCommit
    self.onCancel = onCancel
  }

  var body: some View {
    HStack(spacing: 8) {
      TextField("Title", text: $title)
        .textFieldStyle(.roundedBorder)
        .focused($focusedField, equals: .title)
        .onSubmit(commit)

      TextField("0:00", text: $duration)
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
        .frame(width: 90)
        .focused($focusedField, equals: .duration)
        .onSubmit(commit)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    // Esc cancels. SwiftUI routes this to the focused field's view tree.
    .onExitCommand(perform: onCancel)
    .onAppear {
      // Setting @FocusState during the same run loop pass as the view's first
      // appearance is ignored — the field does not exist yet as far as the
      // focus system is concerned. One tick later it works. This is the
      // standard workaround for first-appearance focus in SwiftUI.
      DispatchQueue.main.async {
        focusedField = .title
      }
    }
    .onChange(of: focusedField) { _, newField in
      // Duration edits are normally replacements (the field is seeded with a
      // complete HH:MM:SS value). Selecting it on entry means the common
      // "click, type, Return" path takes one gesture instead of requiring
      // Cmd-A first. The next run-loop turn is important: AppKit installs its
      // field editor after SwiftUI publishes the focus change.
      guard newField == .duration else { return }
      DispatchQueue.main.async {
        selectDurationText()
      }
    }
  }

  private func commit() {
    onCommit(title, duration)
  }

  private func selectDurationText() {
    guard focusedField == .duration,
      let responder = NSApp.keyWindow?.firstResponder
    else { return }

    // NSTextField edits through a shared NSTextView field editor. Supporting
    // both responders keeps this working across AppKit's focus transitions.
    if let editor = responder as? NSTextView {
      editor.selectAll(nil)
    } else if let field = responder as? NSTextField {
      field.selectText(nil)
    }
  }
}
