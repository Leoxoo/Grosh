import SwiftData
import SwiftUI

/// Someone paid me back: an amount typed on the keypad, the wallet it came into, the day it was paid back (today to
/// begin with) and an optional note. Into the Expense's own wallet it is kept as a Reimbursement of the Expense
/// (ADR-0008); into another wallet it is a transaction there, linked to the Expense (ADR-0010). With `editing`, the same
/// sheet changes an existing Reimbursement, which stays on the Expense.
struct ReimbursementEditor: View {
    let expense: Transaction
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

    private var draftToSave: ReimbursementDraft { draft.withAmount(of: entry, in: currencyCode) }

    var body: some View {
        let check = RuleCheck { try expense.validatePayback(draftToSave, into: wallet) }
        KeypadSheet(
            title: editing == nil ? Text(Strings.Reimbursements.someonePaidMeBackTitle) : Text(Strings.Reimbursements.editReimbursement),
            entry: $entry,
            canSave: check.passes,
            save: save
        ) { fields in
            Section {
                fields.amountRow(Strings.Common.amount, currencyCode: currencyCode, tint: MoneyDirection.moneyIn.tint)
                if editing == nil {
                    WalletPicker(title: Strings.Reimbursements.receivedIn, selection: $wallet)
                }
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                PaybackFooter(problem: check.shownProblem, isElsewhere: expense.isElsewhere(wallet))
            }
        }
        .errorAlert(Strings.Reimbursements.couldntSave, message: $errorMessage)
    }

    private func save() {
        let saved = Log.store.perform("Saving a Reimbursement", errorMessage: &errorMessage) {
            if let editing {
                try editing.update(with: draftToSave)
            } else {
                try expense.recordPayback(draftToSave, into: wallet)
            }
        }
        if saved {
            dismiss()
        }
    }
}
