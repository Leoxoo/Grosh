import SwiftUI

/// The amount editor an Estimated transaction opens to, from the Home bell or its detail. Its real amount is typed on
/// the keypad, and saving confirms it: the Estimated mark, its reminder and its bell item go.
struct EstimatedAmountEditor: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @State private var entry: AmountEntry
    @State private var errorMessage: String?

    init(transaction: Transaction) {
        self.transaction = transaction
        _entry = State(initialValue: AmountEntry(cents: abs(transaction.amountCents)))
    }

    var body: some View {
        KeypadSheet(
            title: Text("Enter Amount"),
            entry: $entry,
            canSave: (entry.cents ?? 0) > 0,
            save: save
        ) { fields in
            Section {
                fields.amountRow("Amount", currencyCode: transaction.amount.currencyCode)
            } footer: {
                Text("\(transaction.categoryName) was estimated from recent transactions in its category. Enter the real amount to confirm it.")
            }
        }
        .errorAlert("Couldn't Save Amount", message: $errorMessage)
    }

    private func save() {
        do {
            try transaction.confirmAmount(cents: entry.cents ?? 0)
            dismiss()
        } catch {
            Log.recurring.failed("Confirming an estimated amount", error)
            errorMessage = error.localizedDescription
        }
    }
}
