import SwiftData
import SwiftUI

/// Someone paid me back: an amount typed on the keypad, the day it was paid back (today to begin with) and an optional
/// note, kept as a Reimbursement of the Expense. With `editing`, the same sheet changes an existing entry.
struct ReimbursementEditor: View {
    /// The Expense that was paid back.
    let expense: Transaction
    /// The entry being edited, or `nil` when adding one.
    var editing: Reimbursement?

    @Environment(\.today) private var today

    var body: some View {
        ReimbursementForm(expense: expense, editing: editing, startingDay: today)
    }
}

/// The form behind ``ReimbursementEditor``, holding the draft from the moment the sheet opens.
private struct ReimbursementForm: View {
    let expense: Transaction
    let editing: Reimbursement?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: ReimbursementDraft
    @State private var entry: AmountEntry
    @State private var errorMessage: String?

    init(expense: Transaction, editing: Reimbursement?, startingDay: CalendarDay) {
        self.expense = expense
        self.editing = editing
        let startingDraft = editing.map { ReimbursementDraft(editing: $0) } ?? ReimbursementDraft(day: startingDay)
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: editing == nil ? AmountEntry() : AmountEntry(cents: startingDraft.amount.cents))
    }

    private var currencyCode: String { expense.amount.currencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: ReimbursementDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        KeypadSheet(
            title: editing == nil ? Text("Someone Paid Me Back") : Text("Edit Reimbursement"),
            entry: $entry,
            canSave: (try? draftToSave.validate()) != nil,
            save: save
        ) { fields in
            Section {
                fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: 1).tint)
                DayStepper(title: "Date", day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                Text("It is kept on the expense, which then counts what is left of it. No transaction is made.")
            }
        }
        .errorAlert("Couldn't Save Reimbursement", message: $errorMessage)
    }

    private func save() {
        do {
            if let editing {
                try editing.update(with: draftToSave)
            } else {
                try Reimbursement.add(draftToSave, to: expense, in: context)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
