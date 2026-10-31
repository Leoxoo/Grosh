import SwiftData
import SwiftUI

/// Forgive the rest: marks a Loan or Debt forgiven, settling whatever is still outstanding without any money moving or
/// any transaction added. The forgiven amount counts in reports as expense (Loan) or income (Debt) under a category
/// the user picks.
struct ForgiveEditor: View {
    /// The Loan or Debt being forgiven.
    let original: Transaction

    @Environment(\.today) private var today

    var body: some View {
        LoanOrDebtSheet(
            unavailableTitle: Strings.DebtsLoans.cantForgive,
            unavailableMessage: Strings.DebtsLoans.onlyLoanOrDebtForgiven
        ) { context in
            try ForgiveDraft(forgiving: original, on: today, in: context)
        } form: { draft in
            ForgiveForm(startingDraft: draft)
        }
    }
}

/// The form behind ``ForgiveEditor``, holding the draft from the moment the sheet opens.
private struct ForgiveForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: ForgiveDraft
    @State private var errorMessage: String?

    init(startingDraft: ForgiveDraft) {
        _draft = State(initialValue: startingDraft)
    }

    private var loanOrDebt: LoanOrDebt { draft.loanOrDebt }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LoanOrDebtWithRow(loanOrDebt: loanOrDebt)
                    LabeledContent(Strings.Common.forgiven) {
                        Text(draft.forgiven.formatted())
                            .monospacedDigit()
                    }
                    DayStepper(title: Strings.Common.date, day: $draft.day)
                    CategoryPicker(title: Strings.Common.category, type: draft.forgivenType, selection: $draft.category)
                    TextField(Strings.Common.note, text: $draft.note, axis: .vertical)
                } footer: {
                    Text(loanOrDebt.kind.forgiveFooter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Strings.DebtsLoans.forgiveTheRest)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.DebtsLoans.forgive, action: forgive)
                        .disabled(!draft.canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 420)
        #endif
        .errorAlert(Strings.DebtsLoans.couldntForgive, message: $errorMessage)
    }

    private func forgive() {
        do {
            try Forgiveness.record(draft, in: context)
            dismiss()
        } catch {
            Log.store.failed("Forgiving a Loan or Debt", error)
            errorMessage = error.localizedDescription
        }
    }
}
