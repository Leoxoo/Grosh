import SwiftData
import SwiftUI

/// Account → Debts & Loans: the open Loans and Debts (who with, what is outstanding, the due date) and the settled
/// ones. Each opens its transaction detail, where payments are recorded.
struct DebtsLoansView: View {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @Environment(\.today) private var today

    var body: some View {
        let list = DebtsAndLoans(transactions)
        List {
            if !list.open.isEmpty {
                Section(Strings.DebtsLoans.open) {
                    ForEach(list.open) { loanOrDebt in
                        LoanOrDebtLink(loanOrDebt: loanOrDebt, today: today)
                    }
                }
            }
            if !list.settled.isEmpty {
                Section(Strings.Common.settled) {
                    ForEach(list.settled) { loanOrDebt in
                        LoanOrDebtLink(loanOrDebt: loanOrDebt, today: today)
                    }
                }
            }
        }
        .overlay {
            if list.open.isEmpty && list.settled.isEmpty {
                ContentUnavailableView(
                    Strings.DebtsLoans.noDebtsOrLoans,
                    systemImage: "person.2",
                    description: Text(Strings.DebtsLoans.noDebtsOrLoansDescription)
                )
            }
        }
        .navigationTitle(Strings.Screens.debtsAndLoans)
    }
}

/// A Loan or Debt that opens its transaction detail.
private struct LoanOrDebtLink: View {
    let loanOrDebt: LoanOrDebt
    let today: CalendarDay

    var body: some View {
        NavigationLink {
            TransactionDetailView(transaction: loanOrDebt.original)
        } label: {
            LoanOrDebtRow(loanOrDebt: loanOrDebt, today: today)
        }
    }
}

/// A Loan or Debt as Debts & Loans and the Home bell list it: who it is with, when it was lent or borrowed, its due
/// date, and what is outstanding (or that it is settled or forgiven).
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
                    Text("\(Image(systemName: "bell")) \(Text(Strings.DebtsLoans.due(due.date().formatted(date: .abbreviated, time: .omitted))))")
                        .font(.caption)
                        .foregroundStyle(due <= today ? .red : .secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if loanOrDebt.isSettled, loanOrDebt.forgiveness != nil {
                    Text(loanOrDebt.owed.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    ForgivenBadge()
                } else if loanOrDebt.isSettled {
                    Text(loanOrDebt.owed.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(Strings.Common.settled)
                        .font(.caption)
                        .foregroundStyle(.settled)
                } else {
                    Text(loanOrDebt.outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(loanOrDebt.kind.outstandingColor)
                    Text(Strings.DebtsLoans.ofOwed(loanOrDebt.owed.formatted()))
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
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
