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
    @Environment(\.modelContext) private var context

    @State private var draft: DebtPaymentDraft

    init(startingDraft: DebtPaymentDraft) {
        _draft = State(initialValue: startingDraft)
    }

    private var loanOrDebt: LoanOrDebt { draft.loanOrDebt }

    var body: some View {
        KeypadSheet(
            title: Text(Strings.DebtsLoans.recordPayment),
            entry: $draft.entry,
            canSave: draft.canSave,
            saving: "Recording a payment",
            failureTitle: Strings.DebtsLoans.couldntRecordPayment,
            save: { try DebtPayment.record(draft, in: context) }
        ) { fields in
            paymentSection(fields)
            if draft.overpaid.cents > 0 {
                overpaymentSection(draft.signedOverpaid)
            }
        }
    }

    private func paymentSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            LoanOrDebtWithRow(loanOrDebt: loanOrDebt)
            LabeledContent(Strings.DebtsLoans.outstanding) {
                Text(loanOrDebt.outstanding.formatted())
                    .monospacedDigit()
            }
            fields.amountRow(Strings.Common.amount, currencyCode: draft.currencyCode, tint: loanOrDebt.kind.paymentDirection.tint)
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
}
