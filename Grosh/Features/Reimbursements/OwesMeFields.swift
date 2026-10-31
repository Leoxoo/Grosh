import SwiftData
import SwiftUI

/// A + Owes me for each Person in With who doesn't owe anything yet, on an Expense (ADR-0010). Use under With, inside a
/// `Form` or `List`.
struct OwesMeAddButtons: View {
    @Binding var draft: TransactionDraft

    var body: some View {
        if draft.offersOwesMe {
            ForEach(draft.people.filter { draft.owesEntry(for: $0) == nil }, id: \.persistentModelID) { person in
                Button {
                    draft.addOwes(person)
                } label: {
                    Label("+ Owes me: \(person.name)", systemImage: "plus.circle")
                }
            }
        }
    }
}

/// Each Person who is yet to pay part of the Expense back, in a section of their own headed with their name, so one
/// Person's amount, reminder and Remove are apart from the next one's: the amount (blank is an open amount, shown as
/// `?`) and a Reminder a week after the Expense (ADR-0010). Nothing here moves any balance or report. Use inside a `Form`
/// or `List`.
struct OwesMeSections: View {
    @Binding var draft: TransactionDraft

    private var currencyCode: String { draft.wallet?.currencyCode ?? Money.defaultCurrencyCode }

    var body: some View {
        ForEach($draft.owes, id: \.person.persistentModelID) { $entry in
            Section("\(entry.person.name) owes me") {
                OwesMeRow(
                    entry: $entry, currencyCode: currencyCode, expenseDay: draft.day,
                    remove: entry.hasPayments ? nil : { draft.removeOwes(entry.person) }
                )
            }
        }
    }
}

/// One Person who owes: their amount, typed on the form's Keypad, and reminder, and Remove unless money has been paid
/// back already.
private struct OwesMeRow: View {
    @Binding var entry: OwesMeDraft
    let currencyCode: String
    let expenseDay: CalendarDay
    /// Takes the row away, or `nil` for one with payments.
    let remove: (() -> Void)?

    @State private var amountEntry: AmountEntry

    init(entry: Binding<OwesMeDraft>, currencyCode: String, expenseDay: CalendarDay, remove: (() -> Void)?) {
        _entry = entry
        self.currencyCode = currencyCode
        self.expenseDay = expenseDay
        self.remove = remove
        _amountEntry = State(initialValue: AmountEntry(cents: entry.wrappedValue.amount?.cents ?? 0))
    }

    var body: some View {
        AmountRow(
            field: OwesMeAmountField(person: entry.person.persistentModelID), entry: $amountEntry,
            currencyCode: currencyCode, placeholder: "?", font: .body
        ) {
            Label("Amount", systemImage: "arrow.uturn.backward.circle")
        }
        .onChange(of: amountEntry) { entry.amount = Self.amount(typed: amountEntry, currencyCode: currencyCode) }
        ReminderField(
            day: $entry.reminderDay, turnsOnAt: ExpectedReimbursement.defaultReminderDay(expenseOn: expenseDay)
        )
        if let remove {
            Button("Remove Owes Me", systemImage: "minus.circle", role: .destructive, action: remove)
        }
    }

    /// What was typed as an amount: nothing is an open amount, and anything that isn't an amount above zero comes to
    /// zero, which saving refuses (``ExpectedReimbursementRuleError/invalidAmount``).
    private static func amount(typed entry: AmountEntry, currencyCode: String) -> Money? {
        guard !entry.isEmpty else { return nil }
        guard let cents = entry.cents, cents > 0 else { return Money(cents: 0, currencyCode: currencyCode) }
        return Money(cents: cents, currencyCode: currencyCode)
    }
}

/// Which Owes me amount the Keypad types into: the one of this Person.
private struct OwesMeAmountField: Hashable {
    let person: PersistentIdentifier
}
