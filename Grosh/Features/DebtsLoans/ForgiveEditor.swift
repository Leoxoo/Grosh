import SwiftData
import SwiftUI

/// Forgive the rest: settles whatever is still outstanding on a Loan or Debt without any money moving. The forgiven
/// amount is recorded as ordinary expense (Loan) or income (Debt) in a category the user picks.
struct ForgiveEditor: View {
    /// The Loan or Debt being forgiven.
    let original: Transaction

    var body: some View {
        LoanOrDebtSheet(
            unavailableTitle: "Can't Forgive",
            unavailableMessage: "Only a Loan or a Debt can be forgiven."
        ) { context in
            try ForgiveDraft(forgiving: original, on: .today, in: context)
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
                    LabeledContent("Forgiven") {
                        Text(draft.forgiven.formatted())
                            .monospacedDigit()
                    }
                    DayStepper(title: "Date", day: $draft.day)
                    CategoryPicker(title: "Category", type: draft.forgivenType, selection: $draft.category)
                    TextField("Note", text: $draft.note, axis: .vertical)
                } footer: {
                    Text(loanOrDebt.kind.forgiveFooter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Forgive the Rest")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Forgive", action: forgive)
                        .disabled(!draft.canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 420)
        #endif
        .errorAlert("Couldn't Forgive", message: $errorMessage)
    }

    private func forgive() {
        do {
            try Forgiveness.record(draft, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
