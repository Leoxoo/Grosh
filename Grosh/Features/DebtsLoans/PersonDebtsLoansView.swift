import SwiftData
import SwiftUI

/// A Person in Show by people that opens their Loans, Debts and Owes me. `onText` is called with the message when the
/// user taps Text.
struct PersonDebtsLink: View {
    let entry: PersonDebtsAndLoans
    let onText: (TextReminder) -> Void

    var body: some View {
        NavigationLink {
            PersonDebtsLoansDetailView(person: entry.person)
        } label: {
            PersonDebtsRow(entry: entry, onText: onText)
        }
    }
}

/// A Person as Show by people lists them: their name, what they owe the user (Loans plus Owes me) in green and what the
/// user owes them (Debts) in red, one amount per currency and never netted, "+1 open" for Owes me with no amount, and
/// Settled once nothing is outstanding. A Text button sits on the row when the Person has a phone number and something
/// is outstanding.
struct PersonDebtsRow: View {
    let entry: PersonDebtsAndLoans
    let onText: (TextReminder) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.person.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if entry.isSettled {
                    Text("Settled")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    ForEach(entry.owesYou, id: \.currencyCode) { amount in
                        Text("Owes you \(amount.formatted())")
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                    ForEach(entry.youOwe, id: \.currencyCode) { amount in
                        Text("You owe \(amount.formatted())")
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
                    if entry.hasOpenAmounts {
                        Text("+\(entry.openAmountCount) open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if entry.canText {
                Button {
                    onText(TextReminder(entry))
                } label: {
                    Label("Text", systemImage: "message")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Text \(entry.person.name)")
            }
        }
    }
}

/// What a Person in Show by people opens: the same figures as their row, then their Loans, Debts and Owes me, each its
/// own section and each opening its own detail. It reads the lists itself, so a payment recorded in a detail is
/// reflected when the user comes back.
struct PersonDebtsLoansDetailView: View {
    let person: Person

    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @Query(ExpectedReimbursements.all) private var expectations: [ExpectedReimbursement]
    /// The message being texted, while Text them is open.
    @State private var texting: TextReminder?

    var body: some View {
        let entry = DebtsAndLoansByPerson(DebtsAndLoans(transactions), ExpectedReimbursements(expectations))
            .entry(for: person)
        List {
            if let entry {
                Section {
                    PersonDebtsRow(entry: entry) { texting = $0 }
                }
                if !entry.loans.isEmpty {
                    Section("Loans") {
                        ForEach(entry.loans) { loan in
                            LoanOrDebtLink(loanOrDebt: loan)
                        }
                    }
                }
                if !entry.debts.isEmpty {
                    Section("Debts") {
                        ForEach(entry.debts) { debt in
                            LoanOrDebtLink(loanOrDebt: debt)
                        }
                    }
                }
                if !entry.expectations.isEmpty {
                    Section("Owes Me") {
                        ForEach(entry.expectations) { expectation in
                            ExpectedReimbursementLink(expectation: expectation)
                        }
                    }
                }
            }
        }
        .overlay {
            if entry == nil {
                ContentUnavailableView("Nothing Owed", systemImage: "person.2")
            }
        }
        .textThemSheet($texting)
        .navigationTitle(person.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
