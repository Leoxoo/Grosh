import SwiftUI

/// A full-screen, Apple-style empty state for a feature that isn't built yet. Nothing on it is tappable.
struct ComingSoonScreen: View {
    let placeholder: ComingSoon

    var body: some View {
        ContentUnavailableView {
            Label("Coming Soon", systemImage: placeholder.systemImage)
        } description: {
            Text(placeholder.message)
        }
        .navigationTitle(placeholder.title)
    }
}

#Preview {
    NavigationStack {
        ComingSoonScreen(placeholder: .recurringTransactions)
    }
}
