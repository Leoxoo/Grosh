import SwiftData
import SwiftUI

/// Edits a wallet's Starting balance: the money it held when it was added (below zero, typed with a leading minus, for
/// a wallet that started in debt), its date and note. It stays under the Starting balance category and excluded from
/// report.
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
        _entry = State(initialValue: AmountEntry(cents: draft.amount.cents, kind: .balance))
    }

    private var currencyCode: String { transaction.amount.currencyCode }

    /// The draft with the amount the keypad comes to, or `nil` while the keypad shows an error. Zero is a Starting
    /// balance too.
    private var draftToSave: StartingBalanceDraft? {
        entry.cents == nil ? nil : draft.withAmount(of: entry, in: currencyCode)
    }

    var body: some View {
        KeypadSheet(
            title: Text(Strings.Transactions.editStartingBalance), entry: $entry, canSave: draftToSave != nil, save: save
        ) { fields in
            Section {
                if let wallet = transaction.wallet {
                    WalletLabel(title: Strings.Common.wallet, wallet: wallet)
                }
                fields.amountRow(Strings.Common.amount, currencyCode: currencyCode, tint: (draftToSave?.amount.direction ?? .neither).tint)
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                Text(Strings.Transactions.startingBalanceFooter)
            }
        }
        .errorAlert(Strings.Transactions.couldntSaveStartingBalance, message: $errorMessage)
    }

    private func save() {
        guard let draftToSave else { return }
        let succeeded = Log.store.perform("Saving a starting balance", errorMessage: &errorMessage) {
            try transaction.update(with: draftToSave)
        }
        if succeeded {
            dismiss()
        }
    }
}
