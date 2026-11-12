import SwiftUI

/// The amount editor an Estimated transaction opens to, from the Home bell or its detail. Its real amount is typed on
/// the keypad, and saving confirms it: the Estimated mark, its reminder and its bell item go.
struct EstimatedAmountEditor: View {
    let transaction: Transaction

    @State private var draft: EstimatedAmountDraft

    init(transaction: Transaction) {
        self.transaction = transaction
        _draft = State(initialValue: EstimatedAmountDraft(confirming: transaction))
    }

    var body: some View {
        KeypadSheet(
            title: Text(Strings.Transactions.enterAmount),
            entry: $draft.entry,
            canSave: draft.canSave,
            saving: "Confirming an estimated amount",
            failureTitle: Strings.Recurring.couldntSaveAmount,
            log: Log.recurring,
            save: { try transaction.confirmAmount(draft) }
        ) { fields in
            Section {
                fields.amountRow(Strings.Common.amount, currencyCode: draft.currencyCode)
            } footer: {
                Text(Strings.Recurring.estimatedFromRecent(transaction.categoryName))
            }
        }
    }
}
