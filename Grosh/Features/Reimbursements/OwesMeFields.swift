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
            Label("Amount", systemImage: "arrow.uturn.backward.circle")
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
        amount?.plainNumber() ?? ""
    }

    /// What was typed as an amount: blank is an open amount, and anything that isn't an amount above zero comes to zero,
    /// which saving refuses (``ExpectedReimbursementRuleError/invalidAmount``).
    private static func amount(typed text: String, currencyCode: String) -> Money? {
        guard text.nilIfBlank != nil else { return nil }
        let amount = Money(typedAmount: text, currencyCode: currencyCode)
        return amount.flatMap { $0.cents > 0 ? $0 : nil } ?? Money(cents: 0, currencyCode: currencyCode)
    }
}
