import SwiftData
import SwiftUI

/// Someone paid me back: an amount typed on the keypad, the wallet it came into, the day it was paid back (today to
/// begin with) and an optional note. Into the Expense's own wallet it is kept as a Reimbursement of the Expense
/// (ADR-0008); into another wallet it is a transaction there, linked to the Expense (ADR-0010). With `editing`, the same
/// sheet changes an existing Reimbursement, which stays on the Expense.
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
    /// The wallet the money came into. Starts at the Expense's own.
    @State private var wallet: Wallet?
    @State private var errorMessage: String?

    init(expense: Transaction, editing: Reimbursement?, startingDay: CalendarDay) {
        self.expense = expense
        self.editing = editing
        let startingDraft = editing.map(ReimbursementDraft.init(editing:)) ?? ReimbursementDraft(day: startingDay)
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: editing == nil ? AmountEntry() : AmountEntry(cents: startingDraft.amount.cents))
        _wallet = State(initialValue: expense.wallet)
    }

    private var currencyCode: String { expense.amount.currencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: ReimbursementDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    /// Why it can't be saved as it is, or `nil` when it can.
    private var problem: Error? {
        do {
            try draftToSave.validate()
            try expense.checkPayback(into: wallet)
            return nil
        } catch {
            return error
        }
    }

    var body: some View {
        let problem = self.problem
        KeypadSheet(
            title: editing == nil ? Text("Someone Paid Me Back") : Text("Edit Reimbursement"),
            entry: $entry,
            canSave: problem == nil,
            save: save
        ) { fields in
            Section {
                fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: 1).tint)
                if editing == nil {
                    WalletPicker(title: "Received In", selection: $wallet)
                }
                DayStepper(title: "Date", day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                if let problem = problem as? ExpectedReimbursementRuleError {
                    Text(problem.localizedDescription)
                } else if expense.isElsewhere(wallet) {
                    Text("Recorded as money in that wallet, on the day you received it, linked to the expense. The expense shows its net in the Total.")
                } else {
                    Text("Kept on the expense, which then counts what is left of it. No transaction is made.")
                }
            }
        }
        .errorAlert("Couldn't Save Reimbursement", message: $errorMessage)
    }

    private func save() {
        do {
            if let editing {
                try editing.update(with: draftToSave)
            } else if expense.isElsewhere(wallet), let wallet {
                try expense.recordPaybackElsewhere(draftToSave, into: wallet, in: context)
            } else {
                try Reimbursement.add(draftToSave, to: expense, in: context)
            }
            dismiss()
        } catch {
            Log.store.failed("Saving a Reimbursement", error)
            errorMessage = error.localizedDescription
        }
    }
}
