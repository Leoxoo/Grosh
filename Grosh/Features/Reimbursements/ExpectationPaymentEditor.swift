import SwiftData
import SwiftUI

/// Record payment on an Expected reimbursement: the amount received (what is outstanding to begin with), the day it was
/// received, an optional note and the wallet it came into. In the Expense's own wallet it is kept as a Reimbursement of
/// the Expense; in another wallet it becomes a transaction there, linked to the Expense (ADR-0010).
struct ExpectationPaymentEditor: View {
    let expectation: ExpectedReimbursement

    @Environment(\.today) private var today

    var body: some View {
        MadeOnce {
            ExpectationPaymentDraft(paying: expectation, on: today)
        } content: { draft in
            ExpectationPaymentForm(expectation: expectation, startingDraft: draft)
        }
    }
}

/// The form behind ``ExpectationPaymentEditor``, holding the draft from the moment the sheet opens.
private struct ExpectationPaymentForm: View {
    let expectation: ExpectedReimbursement

    @Environment(\.modelContext) private var context

    @State private var draft: ExpectationPaymentDraft

    init(expectation: ExpectedReimbursement, startingDraft: ExpectationPaymentDraft) {
        self.expectation = expectation
        _draft = State(initialValue: startingDraft)
    }

    var body: some View {
        let check = RuleCheck { try expectation.validate(draft) }
        KeypadSheet(
            title: Text(Strings.DebtsLoans.recordPayment),
            entry: $draft.entry,
            canSave: check.passes,
            saving: "Recording a payment on Owes me",
            failureTitle: Strings.DebtsLoans.couldntRecordPayment,
            save: { try expectation.recordPayment(draft) }
        ) { fields in
            Section {
                LabeledContent(Strings.Common.from, value: expectation.personName)
                LabeledContent(Strings.DebtsLoans.outstanding) {
                    Text(expectation.outstanding.formattedOrUnknown)
                        .monospacedDigit()
                }
                fields.amountRow(Strings.Common.amount, currencyCode: draft.currencyCode, tint: MoneyDirection.moneyIn.tint)
                WalletPicker(title: Strings.Reimbursements.receivedIn, selection: $draft.wallet)
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                PaybackFooter(problem: check.shownProblem, isElsewhere: expectation.expense?.isElsewhere(draft.wallet) == true)
            }
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
