import SwiftData
import SwiftUI

/// A sheet that records something against a Loan or Debt, such as Record Payment or Forgive the Rest: `form` with a
/// draft made from the Loan or Debt as it is when the sheet opens or, when no draft can be made, why not.
struct LoanOrDebtSheet<Draft, Form: View>: View {
    /// Shown instead of the form, such as "Can't Record Payment".
    let unavailableTitle: LocalizedStringKey
    let unavailableMessage: LocalizedStringKey
    /// Throws when the transaction isn't a Loan or Debt.
    let makeDraft: (ModelContext) throws -> Draft
    @ViewBuilder let form: (Draft) -> Form

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        if let draft = try? makeDraft(context) {
            form(draft)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    unavailableTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(unavailableMessage)
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

/// Who a Loan was lent to or a Debt borrowed from, as the sheets that record against it show it.
struct LoanOrDebtWithRow: View {
    let loanOrDebt: LoanOrDebt

    var body: some View {
        LabeledContent(loanOrDebt.kind.withTitle, value: loanOrDebt.original.withName)
    }
}
