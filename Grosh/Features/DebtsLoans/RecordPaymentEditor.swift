import SwiftData
import SwiftUI

/// Record payment: money collected on a Loan or repaid on a Debt, on a day. It starts at what is outstanding; the part
/// above it is recorded as ordinary income or expense in a category the user picks.
struct RecordPaymentEditor: View {
    /// The Loan or Debt being paid.
    let original: Transaction

    var body: some View {
        LoanOrDebtSheet(
            unavailableTitle: "Can't Record Payment",
            unavailableMessage: "Only a Loan or a Debt can be paid back."
        ) { context in
            try DebtPaymentDraft(settling: original, on: .today, in: context)
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

    /// The draft with the amount the keypad comes to.
    private var draftToSave: DebtPaymentDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        KeypadSheet(
            title: Text("Record Payment"),
            entry: $entry,
            canSave: draftToSave.canSave,
            save: save
        ) { fields in
            paymentSection(fields)
            if draftToSave.overpaid.cents > 0 {
                overpaymentSection
            }
        }
        .errorAlert("Couldn't Record Payment", message: $errorMessage)
    }

    private func paymentSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            LoanOrDebtWithRow(loanOrDebt: loanOrDebt)
            LabeledContent("Outstanding") {
                Text(loanOrDebt.outstanding.formatted())
                    .monospacedDigit()
            }
            fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: loanOrDebt.kind.paymentSign).tint)
            DayStepper(title: "Date", day: $draft.day)
            fields.noteField($draft.note)
        } footer: {
            Text(loanOrDebt.kind.recordPaymentFooter)
        }
    }

    private var overpaymentSection: some View {
        Section {
            LabeledContent("Above Outstanding") {
                AmountText(
                    amount: Money(
                        cents: draftToSave.overpaid.cents * loanOrDebt.kind.paymentSign, currencyCode: currencyCode
                    ),
                    showsPlusSign: true
                )
            }
            CategoryPicker(title: "Category", type: draft.overpaymentType, selection: $draft.overpaymentCategory)
        } footer: {
            Text(loanOrDebt.kind.overpaymentFooter)
        }
    }

    private func save() {
        do {
            try DebtPayment.record(draftToSave, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
