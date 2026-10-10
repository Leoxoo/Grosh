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
                    ForEach(list.open) { loanOrDebt in
                        LoanOrDebtLink(loanOrDebt: loanOrDebt)
                    }
                }
            }
            if !list.settled.isEmpty {
                Section("Settled") {
                    ForEach(list.settled) { loanOrDebt in
                        LoanOrDebtLink(loanOrDebt: loanOrDebt)
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
    let loanOrDebt: LoanOrDebt

    var body: some View {
        NavigationLink {
            TransactionDetailView(transaction: loanOrDebt.original)
        } label: {
            LoanOrDebtRow(loanOrDebt: loanOrDebt, today: .today)
        }
    }
}

/// A Loan or Debt as Debts & Loans and the Home bell list it: who it is with, when it was lent or borrowed, its due
/// date, and what is outstanding (or that it is settled).
struct LoanOrDebtRow: View {
    let loanOrDebt: LoanOrDebt
    let today: CalendarDay

    private var original: Transaction { loanOrDebt.original }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: original.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(original.withName.isEmpty ? original.categoryName : original.withName)
                    .lineLimit(1)
                Text(loanOrDebt.kind.summary(lentOrBorrowedOn: original.day.date().formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !loanOrDebt.isSettled, let due = original.reminderDay {
                    Text("\(Image(systemName: "bell")) Due \(due.date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(due <= today ? .red : .secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if loanOrDebt.isSettled {
                    Text(loanOrDebt.owed.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("Settled")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text(loanOrDebt.outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(loanOrDebt.kind.outstandingColor)
                    Text("of \(loanOrDebt.owed.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
