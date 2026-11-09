import SwiftData
import SwiftUI

/// Record payment on an Expected reimbursement: the amount received (what is outstanding to begin with), the day it was
/// received, an optional note and the wallet it came into. In the Expense's own wallet it is kept as a Reimbursement of
/// the Expense; in another wallet it becomes a transaction there, linked to the Expense (ADR-0010).
struct ExpectationPaymentEditor: View {
    let expectation: ExpectedReimbursement

    @Environment(\.today) private var today

    var body: some View {
        ExpectationPaymentForm(expectation: expectation, today: today)
    }
}

/// The form behind ``ExpectationPaymentEditor``, holding the draft from the moment the sheet opens.
private struct ExpectationPaymentForm: View {
    let expectation: ExpectedReimbursement

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: ExpectationPaymentDraft
    @State private var entry: AmountEntry
    @State private var errorMessage: String?

    /// `today` is the day the payment starts on.
    init(expectation: ExpectedReimbursement, today: CalendarDay) {
        self.expectation = expectation
        let startingDraft = ExpectationPaymentDraft(paying: expectation, on: today)
        _draft = State(initialValue: startingDraft)
        // An open amount has nothing outstanding to start from, so the keypad starts blank.
        _entry = State(
            initialValue: startingDraft.amount.cents > 0 ? AmountEntry(cents: startingDraft.amount.cents) : AmountEntry()
        )
    }

    private var currencyCode: String { expectation.currencyCode }

    private var draftToSave: ExpectationPaymentDraft { draft.withAmount(of: entry, in: currencyCode) }

    var body: some View {
        let check = RuleCheck { try expectation.validate(draftToSave) }
        KeypadSheet(
            title: Text(Strings.DebtsLoans.recordPayment),
            entry: $entry,
            canSave: check.passes,
            save: save
        ) { fields in
            Section {
                LabeledContent(Strings.Common.from, value: expectation.personName)
                LabeledContent(Strings.DebtsLoans.outstanding) {
                    Text(expectation.outstanding?.formatted() ?? "?")
                        .monospacedDigit()
                }
                fields.amountRow(Strings.Common.amount, currencyCode: currencyCode, tint: MoneyDirection.moneyIn.tint)
                WalletPicker(title: Strings.Reimbursements.receivedIn, selection: $draft.wallet)
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                PaybackFooter(problem: check.shownProblem, isElsewhere: expectation.expense?.isElsewhere(draft.wallet) == true)
            }
        }
        .errorAlert(Strings.DebtsLoans.couldntRecordPayment, message: $errorMessage)
    }

    private func save() {
        let saved = Log.store.perform("Recording a payment on Owes me", errorMessage: &errorMessage) {
            try expectation.recordPayment(draftToSave, in: context)
        }
        if saved {
            dismiss()
        }
    }
}

/// The footer of a sheet that records money paid back on an Expense: why it can't be saved yet, or else where the money
/// goes: kept on the Expense in its own wallet, or a transaction in another one (ADR-0010).
struct PaybackFooter: View {
    let problem: Error?
    let isElsewhere: Bool

    var body: some View {
        if let problem {
            Text(problem.localizedDescription)
        } else if isElsewhere {
            Text(Strings.Reimbursements.elsewhereFooter)
        } else {
            Text(Strings.Reimbursements.editorFooter)
        }
    }
}
