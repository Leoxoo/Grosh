import SwiftData
import SwiftUI

/// Account → Debts & Loans, shown one of two ways, remembered between visits. **Show by Loan/Debt**: the open Loans and
/// Debts (who with, what is outstanding, the due date) and the settled ones. Each opens its transaction detail, where
/// payments are recorded. Owes me has its own sections: the Expected reimbursements still open, headed by what is
/// outstanding and "+1 open" for those with no amount, and the settled ones. Each opens its own detail.
/// **Show by people**: one row per Person with what they owe the user (Loans plus Owes me) and what the user owes them
/// (Debts), apart and never netted, the ones with something outstanding first and then Settled. A row opens the Person's
/// Loans, Debts and Owes me, and has a Text button when the Person has a phone number (ADR-0009, ADR-0010).
struct DebtsLoansView: View {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @Query(ExpectedReimbursements.all) private var expectations: [ExpectedReimbursement]
    @AppStorage(DebtsLoansGrouping.storageKey) private var grouping = DebtsLoansGrouping.default
    /// The message being texted, while Text them is open.
    @State private var texting: TextReminder?

    var body: some View {
        let list = DebtsAndLoans(transactions)
        let owesMe = ExpectedReimbursements(expectations)
        // Only the list on show is grouped by people.
        let people = grouping == .people ? DebtsAndLoansByPerson(list, owesMe) : nil
        let isEmpty = people.map { $0.open.isEmpty && $0.settled.isEmpty }
            ?? (list.open.isEmpty && list.settled.isEmpty && owesMe.open.isEmpty && owesMe.settled.isEmpty)
        List {
            Section {
                Picker("Show", selection: $grouping) {
                    Text("Show by people").tag(DebtsLoansGrouping.people)
                    Text("Show by Loan/Debt").tag(DebtsLoansGrouping.loanOrDebt)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let people {
                byPeople(people)
            } else {
                byLoanOrDebt(list, owesMe)
            }
        }
        .overlay {
            if isEmpty {
                ContentUnavailableView(
                    "No Debts or Loans",
                    systemImage: "person.2",
                    description: Text("Add a Loan or a Debt on the Debt/Loan tab of Add Transaction, or + Owes me on an expense's With.")
                )
            }
        }
        .textThemSheet($texting)
        .navigationTitle("Debts & Loans")
    }

    /// Show by people: the people with something outstanding, then Settled.
    @ViewBuilder
    private func byPeople(_ people: DebtsAndLoansByPerson) -> some View {
        if !people.open.isEmpty {
            Section("Open") {
                ForEach(people.open) { entry in
                    PersonDebtsLink(entry: entry) { texting = $0 }
                }
            }
        }
        if !people.settled.isEmpty {
            Section("Settled") {
                ForEach(people.settled) { entry in
                    PersonDebtsLink(entry: entry) { texting = $0 }
                }
            }
        }
    }

    /// Show by Loan/Debt: the list as it was before people.
    @ViewBuilder
    private func byLoanOrDebt(_ list: DebtsAndLoans, _ owesMe: ExpectedReimbursements) -> some View {
        if !list.open.isEmpty {
            Section("Open") {
                ForEach(list.open) { loanOrDebt in
                    LoanOrDebtLink(loanOrDebt: loanOrDebt)
                }
            }
        }
        if !owesMe.open.isEmpty {
            Section {
                ForEach(owesMe.open) { expectation in
                    ExpectedReimbursementLink(expectation: expectation)
                }
            } header: {
                HStack {
                    Text("Owes Me")
                    Spacer()
                    Text(owesMe.totals.summary)
                        .monospacedDigit()
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
        if !owesMe.settled.isEmpty {
            Section("Owes Me · Settled") {
                ForEach(owesMe.settled) { expectation in
                    ExpectedReimbursementLink(expectation: expectation)
                }
            }
        }
    }
}

/// An Expected reimbursement that opens its detail.
struct ExpectedReimbursementLink: View {
    let expectation: ExpectedReimbursement

    var body: some View {
        NavigationLink {
            ExpectedReimbursementDetailView(expectation: expectation)
        } label: {
            ExpectedReimbursementRow(expectation: expectation, today: .today)
        }
    }
}

/// A Loan or Debt that opens its transaction detail.
struct LoanOrDebtLink: View {
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
                    Text("\(Image(systemName: "bell")) Due \(due.date().formatted(date: .abbreviated, time: .omitted))")
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
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
