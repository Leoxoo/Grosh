import SwiftUI

/// Account's "Recurring transactions" row. It opens a coming-soon screen until the feature is built.
/// Use inside a `List` within a `NavigationStack`.
struct RecurringTransactionsRow: View {
    private let placeholder = ComingSoon.recurringTransactions

    var body: some View {
        NavigationLink {
            ComingSoonScreen(placeholder: placeholder)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } label: {
            Label(placeholder.title, systemImage: placeholder.systemImage)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            RecurringTransactionsRow()
        }
    }
}
