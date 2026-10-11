import SwiftData
import SwiftUI

/// Account → Recurring transactions: every schedule, grouped by Kind and in the order it was added within each group.
/// Tap one to see what it has made, and add one with the plus.
struct RecurringTransactionsView: View {
    @Query(sort: \RecurringTransaction.createdAt) private var recurring: [RecurringTransaction]
    @State private var editorMode: EditorMode<RecurringTransaction>?

    var body: some View {
        List {
            ForEach(RecurringListing.groups(of: recurring)) { group in
                Section(group.kind.sectionTitle) {
                    ForEach(group.items) { item in
                        NavigationLink {
                            RecurringTransactionDetailView(recurring: item)
                        } label: {
                            RecurringTransactionRow(recurring: item)
                        }
                    }
                }
            }
        }
        .overlay {
            if recurring.isEmpty {
                ContentUnavailableView {
                    Label("No Recurring Transactions", systemImage: "repeat")
                } description: {
                    Text("Bills, subscriptions and income that repeat are added for you on their dates.")
                } actions: {
                    Button("Add Recurring Transaction") { editorMode = .add }
                }
            }
        }
        .navigationTitle("Recurring transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Recurring Transaction", systemImage: "plus") { editorMode = .add }
            }
        }
        .sheet(item: $editorMode) { mode in
            RecurringTransactionEditor(mode: mode)
        }
    }
}

/// One Recurring transaction in the list: its icon, name, wallet and next day, and its signed amount.
struct RecurringTransactionRow: View {
    let recurring: RecurringTransaction

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: recurring.category, subscriptionIcon: recurring.subscriptionIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text(recurring.name)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            AmountText(amount: recurring.signedAmount)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The wallet and the next day it falls due, such as "Checking · Next Nov 4, 2026".
    private var detail: String {
        let wallet = recurring.wallet?.name ?? String(localized: "No wallet")
        guard let next = recurring.nextDueDay else {
            return String(localized: "\(wallet) · Ended")
        }
        let day = next.date().formatted(.dateTime.day().month(.abbreviated).year())
        return String(localized: "\(wallet) · Next \(day)")
    }
}
