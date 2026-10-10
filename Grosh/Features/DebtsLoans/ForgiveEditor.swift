import SwiftData
import SwiftUI

/// Forgive the rest: settles whatever is still outstanding on a Loan or Debt without any money moving. The forgiven
/// amount is recorded as ordinary expense (Loan) or income (Debt) in a category the user picks.
struct ForgiveEditor: View {
    /// The Loan or Debt being forgiven.
    let original: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        if let draft = try? ForgiveDraft(forgiving: original, on: .today, in: context) {
            ForgiveForm(startingDraft: draft)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Can't Forgive",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Only a Loan or a Debt can be forgiven.")
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
                    LabeledContent(loanOrDebt.isLoan ? "Lent To" : "Borrowed From", value: loanOrDebt.original.withName)
                    LabeledContent("Forgiven") {
                        Text(draft.forgiven.formatted())
                            .monospacedDigit()
                    }
                    DayStepper(title: "Date", day: $draft.day)
                    CategoryPicker(title: "Category", type: draft.forgivenType, selection: $draft.category)
                    TextField("Note", text: $draft.note, axis: .vertical)
                } footer: {
                    Text(loanOrDebt.isLoan
                        ? "Settles the Loan with a Debt Collection and an expense of the same amount, so no balance changes. The expense counts in reports."
                        : "Settles the Debt with a Repayment and an income of the same amount, so no balance changes. The income counts in reports.")
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
