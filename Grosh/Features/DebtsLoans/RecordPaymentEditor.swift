import SwiftData
import SwiftUI

/// Record payment: money collected on a Loan or repaid on a Debt, on a day. It starts at what is outstanding; the part
/// above it is recorded as ordinary income or expense in a category the user picks.
struct RecordPaymentEditor: View {
    /// The Loan or Debt being paid.
    let original: Transaction

    @Environment(\.today) private var today

    var body: some View {
        LoanOrDebtSheet(
            unavailableTitle: Strings.DebtsLoans.cantRecordPayment,
            unavailableMessage: Strings.DebtsLoans.onlyLoanOrDebtPaidBack
        ) { context in
            try DebtPaymentDraft(settling: original, on: today, in: context)
        } form: { draft in
            RecordPaymentForm(startingDraft: draft)
        }
    }
}

/// The form behind ``RecordPaymentEditor``, holding the draft from the moment the sheet opens.
private struct RecordPaymentForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: DebtPaymentDraft
    @State private var entry: AmountEntry
    @State private var errorMessage: String?

    init(startingDraft: DebtPaymentDraft) {
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: AmountEntry(cents: startingDraft.amount.cents))
    }

    private var loanOrDebt: LoanOrDebt { draft.loanOrDebt }
    private var currencyCode: String { loanOrDebt.owed.currencyCode }

    private var draftToSave: DebtPaymentDraft { draft.withAmount(of: entry, in: currencyCode) }

    var body: some View {
        let draftToSave = self.draftToSave
        KeypadSheet(
            title: Text(Strings.DebtsLoans.recordPayment),
            entry: $entry,
            canSave: draftToSave.canSave,
            save: save
        ) { fields in
            paymentSection(fields)
            if draftToSave.overpaid.cents > 0 {
                overpaymentSection(draftToSave.signedOverpaid)
            }
        }
        .errorAlert(Strings.DebtsLoans.couldntRecordPayment, message: $errorMessage)
    }

    private func paymentSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            LoanOrDebtWithRow(loanOrDebt: loanOrDebt)
            LabeledContent(Strings.DebtsLoans.outstanding) {
                Text(loanOrDebt.outstanding.formatted())
                    .monospacedDigit()
            }
            fields.amountRow(Strings.Common.amount, currencyCode: currencyCode, tint: loanOrDebt.kind.paymentDirection.tint)
            DayStepper(title: Strings.Common.date, day: $draft.day)
            fields.noteField($draft.note)
        } footer: {
            Text(loanOrDebt.kind.recordPaymentFooter)
        }
    }

    private func overpaymentSection(_ overpaid: Money) -> some View {
        Section {
            LabeledContent(Strings.DebtsLoans.aboveOutstanding) {
                AmountText(amount: overpaid, showsPlusSign: true)
            }
            CategoryPicker(title: Strings.Common.category, type: draft.overpaymentType, selection: $draft.overpaymentCategory)
        } footer: {
            Text(loanOrDebt.kind.overpaymentFooter)
        }
    }

    private func save() {
        let succeeded = Log.store.perform("Recording a payment", errorMessage: &errorMessage) {
            try DebtPayment.record(draftToSave, in: context)
        }
        if succeeded {
            dismiss()
        }
    }
}
