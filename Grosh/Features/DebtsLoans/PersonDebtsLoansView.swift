import SwiftData
import SwiftUI

/// A Person in Show by people that opens their Loans, Debts and Owes me. `onText` is called with the message when the
/// user taps Text.
struct PersonDebtsLink: View {
    let entry: PersonDebtsAndLoans
    let onText: (TextReminder) -> Void

    var body: some View {
        NavigationLink {
            PersonDebtsLoansDetailView(entry: entry)
                .equatable()
        } label: {
            PersonDebtsRow(entry: entry, onText: onText)
        }
    }
}

/// A Person as Show by people lists them: their name, what they owe the user (Loans plus Owes me) in green and what the
/// user owes them (Debts) in red, one amount per currency and never netted, "+1 open" for Owes me with no amount, and
/// Settled once nothing is outstanding. A Text button sits on the row while something is outstanding.
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
                    Text(Strings.Common.settled)
                        .font(.caption)
                        .foregroundStyle(.settled)
                } else {
                    ForEach(entry.owesYou, id: \.currencyCode) { amount in
                        Text(Strings.People.owesYou(amount.formatted()))
                            .monospacedDigit()
                            .foregroundStyle(.moneyIn)
                    }
                    ForEach(entry.youOwe, id: \.currencyCode) { amount in
                        Text(Strings.People.youOwe(amount.formatted()))
                            .monospacedDigit()
                            .foregroundStyle(.moneyOut)
                    }
                    if entry.hasOpenAmounts {
                        Text(Strings.OwesMe.openCount(entry.openAmountCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if entry.canText {
                Button {
                    onText(TextReminder(entry))
                } label: {
                    Label(Strings.People.text, systemImage: "message")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Strings.People.textName(entry.person.name))
            }
        }
    }
}

/// What a Person in Show by people opens: the same figures as their row, then their Loans, Debts and Owes me, each its
/// own section and each opening its own detail. Show by people hands it the Person's entry, a new one whenever the
/// store changes, so a payment recorded in a detail is reflected when the user comes back.
struct PersonDebtsLoansDetailView: View {
    let entry: PersonDebtsAndLoans

    /// The message being texted, while Text them is open.
    @State private var texting: TextReminder?

    var body: some View {
        List {
            Section {
                PersonDebtsRow(entry: entry) { texting = $0 }
            }
            if !entry.loans.isEmpty {
                Section(Strings.DebtsLoans.loans) {
                    ForEach(entry.loans) { loan in
                        LoanOrDebtLink(loanOrDebt: loan)
                    }
                }
            }
            if !entry.debts.isEmpty {
                Section(Strings.DebtsLoans.debts) {
                    ForEach(entry.debts) { debt in
                        LoanOrDebtLink(loanOrDebt: debt)
                    }
                }
            }
            if !entry.expectations.isEmpty {
                Section(Strings.OwesMe.owesMe) {
                    ForEach(entry.expectations) { expectation in
                        ExpectedReimbursementLink(expectation: expectation)
                    }
                }
            }
        }
        .textThemSheet($texting)
        .navigationTitle(entry.person.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Debts & Loans hands the screen a newly made entry each time it redraws, and it redraws whenever the navigation stack
/// does, which redrawing this screen makes it do. Compared as a view, a new entry always counted as a change, so the two
/// kept redrawing each other and the app froze. Compared as an entry, every field included, a new one is the same until
/// it shows something else: another Person, other figures, or other Loans, Debts, payments or Owes me. Each row updates
/// itself from its own Loan, Debt or Owes me.
extension PersonDebtsLoansDetailView: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.entry == rhs.entry }
}
