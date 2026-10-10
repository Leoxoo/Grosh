import SwiftData
import SwiftUI

/// Account → Debts & Loans: the open Loans and Debts (who with, what is outstanding, the due date) and the settled
/// ones. Each opens its transaction detail, where payments are recorded.
struct DebtsLoansView: View {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]

    var body: some View {
        let list = DebtsAndLoans(transactions)
        List {
            if !list.open.isEmpty {
                Section("Open") {
                    ForEach(list.open) { item in
                        LoanOrDebtLink(item: item)
                    }
                }
            }
            if !list.settled.isEmpty {
                Section("Settled") {
                    ForEach(list.settled) { item in
                        LoanOrDebtLink(item: item)
                    }
                }
            }
        }
        .overlay {
            if list.open.isEmpty && list.settled.isEmpty {
                ContentUnavailableView(
                    "No Debts or Loans",
                    systemImage: "person.2",
                    description: Text("Add a Loan or a Debt on the Debt/Loan tab of Add Transaction.")
                )
            }
        }
        .navigationTitle("Debts & Loans")
    }
}

/// A Loan or Debt that opens its transaction detail.
private struct LoanOrDebtLink: View {
    let item: LoanOrDebt

    var body: some View {
        NavigationLink {
            TransactionDetailView(transaction: item.original)
        } label: {
            LoanOrDebtRow(item: item, today: .today)
        }
    }
}

/// A Loan or Debt as Debts & Loans and the Home bell list it: who it is with, when it was lent or borrowed, its due
/// date, and what is outstanding (or that it is settled).
struct LoanOrDebtRow: View {
    let item: LoanOrDebt
    let today: CalendarDay

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.original.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.original.withName.isEmpty ? item.original.categoryName : item.original.withName)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.isSettled, let due = item.original.reminderDay {
                    Text("\(Image(systemName: "bell")) Due \(due.date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(due <= today ? .red : .secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if item.isSettled {
                    Text(item.owed.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("Settled")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(item.outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(item.isLoan ? .green : .red)
                    Text("of \(item.owed.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Loan · May 27, 2026" or "Debt · May 27, 2026".
    private var summary: String {
        let day = item.original.day.date().formatted(date: .abbreviated, time: .omitted)
        return item.isLoan ? String(localized: "Loan · \(day)") : String(localized: "Debt · \(day)")
    }
}

extension LoanOrDebt: Identifiable {
    var id: PersistentIdentifier { original.persistentModelID }
}

#Preview {
    NavigationStack {
        DebtsLoansView()
    }
    .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
