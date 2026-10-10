import SwiftData
import SwiftUI

/// Edits a wallet's Starting balance: the money it held when it was added (below zero for a wallet that started
/// in debt), its date and note. It stays under the Starting balance category and excluded from report.
struct StartingBalanceEditor: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: StartingBalanceDraft
    @State private var entry: AmountEntry
    @State private var errorMessage: String?

    init(transaction: Transaction) {
        self.transaction = transaction
        let draft = StartingBalanceDraft(editing: transaction)
        _draft = State(initialValue: draft)
        _entry = State(initialValue: AmountEntry(cents: draft.amount.cents))
    }

    private var currencyCode: String { transaction.amount.currencyCode }

    /// The draft with the amount the keypad comes to, or `nil` while the keypad shows an error.
    private var draftToSave: StartingBalanceDraft? {
        guard let cents = entry.cents else { return nil }
        var result = draft
        result.amount = Money(cents: cents, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        KeypadSheet(
            title: Text("Edit Starting Balance"), entry: $entry, canSave: draftToSave != nil, save: save
        ) { fields in
            Section {
                if let wallet = transaction.wallet {
                    WalletLabel(title: "Wallet", wallet: wallet)
                }
                fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: entry.cents ?? 0).tint)
                ChangeSignButton(entry: $entry)
                DayStepper(title: "Date", day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                Text("The money this wallet held when it was added, below zero if it started in debt. It is always excluded from report.")
            }
        }
        .errorAlert("Couldn't Save Starting Balance", message: $errorMessage)
    }

    private func save() {
        guard let draftToSave else { return }
        do {
            try transaction.update(with: draftToSave)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
