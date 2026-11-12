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
        MadeOnce {
            editing.map(ReimbursementDraft.init(editing:)) ?? ReimbursementDraft(payingBack: expense, on: today)
        } content: { draft in
            ReimbursementForm(expense: expense, editing: editing, startingDraft: draft)
        }
    }
}

/// The form behind ``ReimbursementEditor``, holding the draft from the moment the sheet opens.
private struct ReimbursementForm: View {
    let expense: Transaction
    let editing: Reimbursement?

    @Environment(\.modelContext) private var context

    @State private var draft: ReimbursementDraft
    /// The wallet the money came into. Starts at the Expense's own.
    @State private var wallet: Wallet?

    init(expense: Transaction, editing: Reimbursement?, startingDraft: ReimbursementDraft) {
        self.expense = expense
        self.editing = editing
        _draft = State(initialValue: startingDraft)
        _wallet = State(initialValue: expense.wallet)
    }

    var body: some View {
        let check = RuleCheck { try expense.validatePayback(draft, into: wallet) }
        KeypadSheet(
            title: editing == nil ? Text(Strings.Reimbursements.someonePaidMeBackTitle) : Text(Strings.Reimbursements.editReimbursement),
            entry: $draft.entry,
            canSave: check.passes,
            saving: "Saving a Reimbursement",
            failureTitle: Strings.Reimbursements.couldntSave,
            save: save
        ) { fields in
            Section {
                fields.amountRow(Strings.Common.amount, currencyCode: draft.currencyCode, tint: MoneyDirection.moneyIn.tint)
                if editing == nil {
                    WalletPicker(title: Strings.Reimbursements.receivedIn, selection: $wallet)
                }
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                PaybackFooter(problem: check.shownProblem, isElsewhere: expense.isElsewhere(wallet))
            }
        }
    }

    private func save() throws {
        if let editing {
            try editing.update(with: draft)
        } else {
            try expense.recordPayback(draft, into: wallet, in: context)
        }
    }
}
