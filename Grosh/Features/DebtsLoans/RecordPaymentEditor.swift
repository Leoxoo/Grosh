import SwiftData
import SwiftUI

/// Record payment: money collected on a Loan or repaid on a Debt, on a day. It starts at what is outstanding; the part
/// above it is recorded as ordinary income or expense in a category the user picks.
struct RecordPaymentEditor: View {
    /// The Loan or Debt being paid.
    let original: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        if let draft = try? DebtPaymentDraft(settling: original, on: .today, in: context) {
            RecordPaymentForm(startingDraft: draft)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Can't Record Payment",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Only a Loan or a Debt can be paid back.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
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
            LabeledContent(loanOrDebt.isLoan ? "Lent To" : "Borrowed From", value: loanOrDebt.original.withName)
            LabeledContent("Outstanding") {
                Text(loanOrDebt.outstanding.formatted())
                    .monospacedDigit()
            }
            fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: loanOrDebt.paymentSign).tint)
            DayStepper(title: "Date", day: $draft.day)
            fields.noteField($draft.note)
        } footer: {
            Text(loanOrDebt.isLoan
                ? "Recorded as a Debt Collection in the Loan's wallet, excluded from report. The Loan itself doesn't change."
                : "Recorded as a Repayment from the Debt's wallet, excluded from report. The Debt itself doesn't change.")
        }
    }

    private var overpaymentSection: some View {
        Section {
            LabeledContent("Above Outstanding") {
                AmountText(
                    amount: Money(cents: draftToSave.overpaid.cents * loanOrDebt.paymentSign, currencyCode: currencyCode),
                    showsPlusSign: true
                )
            }
            CategoryPicker(title: "Category", type: draft.overpaymentType, selection: $draft.overpaymentCategory)
        } footer: {
            Text(loanOrDebt.isLoan
                ? "What's paid above the outstanding amount is recorded as income and counts in reports."
                : "What's paid above the outstanding amount is recorded as an expense and counts in reports.")
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
