import SwiftUI

/// Shown when there are no tasks. Names the exact next step rather than just
/// saying the list is empty.
struct EmptyStateView: View {
  var body: some View {
    Text("No tasks yet — press + to add one")
      .font(.callout)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 28)
  }
}
