import SwiftData
import SwiftUI

/// The "Owes me" rows of an Expense's more details, under With: each Person who is yet to pay part of it back, with the
/// amount (blank is an open amount, shown as `?`) and a Reminder a week after the Expense, then a + Owes me for each
/// Person in With who has none (ADR-0010). Nothing here moves any balance or report. Use inside a `Form` or `List`.
struct OwesMeField: View {
    @Binding var draft: TransactionDraft

    private var currencyCode: String { draft.wallet?.currencyCode ?? Money.defaultCurrencyCode }

    /// The people in With who don't owe anything yet.
    private var peopleToAdd: [Person] {
        draft.people.filter { draft.owesEntry(for: $0) == nil }
    }

    var body: some View {
        ForEach($draft.owes, id: \.person.persistentModelID) { $entry in
            OwesMeRow(
                entry: $entry, currencyCode: currencyCode, expenseDay: draft.day,
                remove: entry.hasPayments ? nil : { draft.removeOwes(entry.person) }
            )
        }
        if draft.offersOwesMe {
            ForEach(peopleToAdd, id: \.persistentModelID) { person in
                Button {
                    draft.addOwes(person)
                } label: {
                    Label("+ Owes me: \(person.name)", systemImage: "plus.circle")
                }
            }
        }
    }
}

/// One Person who owes: their amount and reminder, and Remove unless money has been paid back already.
private struct OwesMeRow: View {
    @Binding var entry: OwesMeDraft
    let currencyCode: String
    let expenseDay: CalendarDay
    /// Takes the row away, or `nil` for one with payments.
    let remove: (() -> Void)?

    @State private var text = ""

    var body: some View {
        LabeledContent {
            TextField("?", text: $text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(maxWidth: 120)
        } label: {
            Label("\(entry.person.name) owes me", systemImage: "arrow.uturn.backward.circle")
        }
        .onAppear { text = Self.text(of: entry.amount) }
        .onChange(of: text) { entry.amount = Self.amount(typed: text, currencyCode: currencyCode) }
        ReminderField(
            day: $entry.reminderDay, turnsOnAt: ExpectedReimbursement.defaultReminderDay(expenseOn: expenseDay)
        )
        if let remove {
            Button("Remove Owes Me", systemImage: "minus.circle", role: .destructive, action: remove)
        }
    }

    /// The amount as the field shows it: no cents when whole, and blank for an open amount.
    private static func text(of amount: Money?) -> String {
        guard let amount else { return "" }
        let fractionLength = amount.cents % 100 == 0 ? 0 : 2
        return amount.decimalValue.formatted(.number.precision(.fractionLength(fractionLength)))
    }

    /// What was typed as an amount: blank is an open amount, and anything that isn't an amount above zero comes to zero,
    /// which saving refuses (``ExpectedReimbursementRuleError/invalidAmount``).
    private static func amount(typed text: String, currencyCode: String) -> Money? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let amount = Money(typedAmount: text, currencyCode: currencyCode)
        return amount.flatMap { $0.cents > 0 ? $0 : nil } ?? Money(cents: 0, currencyCode: currencyCode)
    }
}
