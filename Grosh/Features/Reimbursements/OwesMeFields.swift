import SwiftData
import SwiftUI

/// A + Owes me for each Person in With who doesn't owe anything yet, on an Expense (ADR-0010). Use under With, inside a
/// `Form` or `List`.
struct OwesMeAddButtons: View {
    @Binding var draft: TransactionDraft

    var body: some View {
        ForEach(draft.peopleOfferedOwesMe, id: \.persistentModelID) { person in
            Button {
                draft.addOwes(person)
            } label: {
                Label(Strings.OwesMe.addOwesMe(person.name), systemImage: "plus.circle")
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

    private var currencyCode: String { draft.wallet.currencyCodeOrDefault }

    var body: some View {
        ForEach($draft.owes, id: \.person.persistentModelID) { $entry in
            Section(String(localized: Strings.OwesMe.personOwesMe(entry.person.name))) {
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

    var body: some View {
        AmountRow(
            field: OwesMeAmountField(person: entry.person.persistentModelID), entry: typedAmount,
            currencyCode: currencyCode, placeholder: Strings.OwesMe.unknownAmount, font: .body
        ) {
            Label(Strings.Common.amount, systemImage: "arrow.uturn.backward.circle")
        }
        ReminderField(day: $entry.reminderDay, countingFrom: expenseDay)
        if let remove {
            Button(Strings.OwesMe.removeOwesMe, systemImage: "minus.circle", role: .destructive, action: remove)
        }
    }

    /// The amount on the Keypad, which the draft takes as an open amount or an amount (``OwesMeDraft/setAmount(typed:in:)``).
    private var typedAmount: Binding<AmountEntry> {
        Binding(
            get: { entry.typedAmount },
            set: { entry.setAmount(typed: $0, in: currencyCode) }
        )
    }
}

/// Which Owes me amount the Keypad types into: the one of this Person.
private struct OwesMeAmountField: Hashable {
    let person: PersistentIdentifier
}
