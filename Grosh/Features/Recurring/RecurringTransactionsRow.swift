import SwiftData
import SwiftUI

/// Account's "Recurring transactions" row, which opens the list of schedules. Use inside a `List` within a
/// `NavigationStack`.
struct RecurringTransactionsRow: View {
    var body: some View {
        NavigationLink {
            RecurringTransactionsView()
        } label: {
            Label("Recurring transactions", systemImage: "repeat")
        }
    }
}

#Preview {
    NavigationStack {
        List {
            RecurringTransactionsRow()
        }
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
