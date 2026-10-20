import SwiftData
import SwiftUI

/// Record payment on an Expected reimbursement: the amount received (what is outstanding to begin with), the day it was
/// received, an optional note and the wallet it came into. In the Expense's own wallet it is kept as a Reimbursement of
/// the Expense; in another wallet it becomes a transaction there, linked to the Expense (ADR-0010).
struct ExpectationPaymentEditor: View {
    let expectation: ExpectedReimbursement

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: ExpectationPaymentDraft
    @State private var entry: AmountEntry
    @State private var errorMessage: String?

    init(expectation: ExpectedReimbursement) {
        self.expectation = expectation
        let startingDraft = ExpectationPaymentDraft(paying: expectation, on: .today)
        _draft = State(initialValue: startingDraft)
        // An open amount has nothing outstanding to start from, so the keypad starts blank.
        _entry = State(
            initialValue: startingDraft.amount.cents > 0 ? AmountEntry(cents: startingDraft.amount.cents) : AmountEntry()
        )
    }

    private var currencyCode: String { expectation.currencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: ExpectationPaymentDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    /// Why the payment can't be recorded as it is, or `nil` when it can.
    private var problem: Error? {
        do {
            try expectation.validate(draftToSave)
            return nil
        } catch {
            return error
        }
    }

    var body: some View {
        let problem = self.problem
        KeypadSheet(
            title: Text("Record Payment"),
            entry: $entry,
            canSave: problem == nil,
            save: save
        ) { fields in
            Section {
                LabeledContent("From", value: expectation.personName)
                LabeledContent("Outstanding") {
                    Text(expectation.outstanding?.formatted() ?? "?")
                        .monospacedDigit()
                }
                fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: 1).tint)
                WalletPicker(title: "Received In", selection: $draft.wallet)
                DayStepper(title: "Date", day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                if let problem = problem as? ExpectedReimbursementRuleError, problem == .otherCurrency {
                    Text(problem.localizedDescription)
                } else if expectation.isElsewhere(draft.wallet) {
                    Text("Recorded as money in that wallet, on the day you received it, linked to the expense. The expense shows its net in the Total.")
                } else {
                    Text("Kept on the expense, which then counts what is left of it. No transaction is made.")
                }
            }
        }
        .errorAlert("Couldn't Record Payment", message: $errorMessage)
    }

    private func save() {
        do {
            try expectation.recordPayment(draftToSave, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
