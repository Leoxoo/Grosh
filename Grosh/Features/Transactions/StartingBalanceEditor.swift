import SwiftData
import SwiftUI

/// Edits a wallet's Starting balance: the money it held when it was added (below zero, typed with a leading minus, for
/// a wallet that started in debt), its date and note. It stays under the Starting balance category and excluded from
/// report.
struct StartingBalanceEditor: View {
    let transaction: Transaction

    @State private var draft: StartingBalanceDraft

    init(transaction: Transaction) {
        self.transaction = transaction
        _draft = State(initialValue: StartingBalanceDraft(editing: transaction))
    }

    var body: some View {
        KeypadSheet(
            title: Text(Strings.Transactions.editStartingBalance), entry: $draft.entry, canSave: draft.canSave,
            saving: "Saving a starting balance", failureTitle: Strings.Transactions.couldntSaveStartingBalance,
            save: { try transaction.update(with: draft) }
        ) { fields in
            Section {
                if let wallet = transaction.wallet {
                    WalletLabel(title: Strings.Common.wallet, wallet: wallet)
                }
                fields.amountRow(Strings.Common.amount, currencyCode: draft.currencyCode, tint: draft.amount.direction.tint)
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                Text(Strings.Transactions.startingBalanceFooter)
            }
        }
    }
}
