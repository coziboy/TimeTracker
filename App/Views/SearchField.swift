import AppKit
import Observation
import SwiftUI

/// Whether the search field holds the keyboard, shared between SwiftUI and
/// the AppKit key monitor.
///
/// `@FocusState` only exists inside a view, but the monitor needs to both
/// request focus (⌘F) and know when to let typing through. `SearchField`
/// mirrors its `@FocusState` into this flag and follows changes made here.
@MainActor
@Observable
final class SearchFocus {
  var isFocused = false
}

/// The compact filter field at the top of the popover: a magnifying glass,
/// the text, and a clear button while there is something to clear.
struct SearchField: View {
  @Binding var query: String
  let focus: SearchFocus

  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search", text: $query)
        .textFieldStyle(.plain)
        .focused($isFocused)

      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Clear search")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color.primary.opacity(0.06))
    )
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 2)
    .onChange(of: isFocused) { _, newValue in
      focus.isFocused = newValue
    }
    .onChange(of: focus.isFocused) { _, newValue in
      isFocused = newValue
    }
    .onAppear {
      // Same first-appearance workaround as `InlineEditor`: a focus request
      // made before the field exists is ignored, so apply it one tick later.
      guard focus.isFocused else { return }
      DispatchQueue.main.async {
        isFocused = focus.isFocused
      }
    }
    .onDisappear {
      // A hidden field cannot hold the keyboard; don't let the key monitor
      // keep passing plain keys through on its behalf.
      focus.isFocused = false
    }
  }
}
