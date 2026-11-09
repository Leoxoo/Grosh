import SwiftData
import SwiftUI

/// Edits one half of a transfer: its amount, date and note. Its wallets stay as the transfer recorded them. When
/// the amount or date changes, Save asks whether to update the other half too, or only this one (as when a fee
/// was taken).
struct TransferHalfEditor: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: TransferHalfDraft
    @State private var entry: AmountEntry
    @State private var isAskingScope = false
    @State private var errorMessage: String?

    init(transaction: Transaction) {
        self.transaction = transaction
        let draft = TransferHalfDraft(editing: transaction)
        _draft = State(initialValue: draft)
        _entry = State(initialValue: AmountEntry(cents: draft.amount.cents))
    }

    private var currencyCode: String { transaction.amount.currencyCode }

    private var draftToSave: TransferHalfDraft { draft.withAmount(of: entry, in: currencyCode) }

    var body: some View {
        KeypadSheet(
            title: Text(transaction.categoryName), entry: $entry, canSave: draftToSave.canSave, save: confirmSave
        ) { fields in
            Section {
                wallets
                fields.amountRow(
                    Strings.Common.amount, currencyCode: currencyCode,
                    tint: MoneyDirection(category: transaction.category).tint
                )
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                Text(Strings.Transfers.halfFooter)
            }
        }
        .confirmationDialog(
            Strings.Transfers.updateOtherHalfQuestion,
            isPresented: $isAskingScope,
            titleVisibility: .visible
        ) {
            Button(Strings.Transfers.updateBoth) { save(.bothHalves) }
            Button(Strings.Common.onlyThisOne) { save(.onlyThisOne) }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Transfers.onlyThisOneFooter)
        }
        .errorAlert(Strings.Transfers.couldntSave, message: $errorMessage)
    }

    /// Where the money left and where it went: this half's wallet and, while it is there, the other half's, read once
    /// when the sheet opens.
    private var wallets: some View {
        MadeOnce {
            Log.store.attempt("Reading the wallets of a transfer") { try transaction.transferWallets(in: context) }
        } content: { wallets in
            WalletLabel(title: Strings.Common.from, wallet: wallets?.from)
            WalletLabel(title: Strings.Common.to, wallet: wallets?.to)
        }
    }

    /// Saves straight away, or first asks whether to update both halves when the amount or date changed.
    private func confirmSave() {
        var asksScope = false
        let checked = Log.store.perform("Checking the other half of a transfer", errorMessage: &errorMessage) {
            asksScope = try transaction.offersToUpdateOtherHalf(with: draftToSave, in: context)
        }
        guard checked else { return }
        if asksScope {
            isAskingScope = true
        } else {
            save(.onlyThisOne)
        }
    }

    private func save(_ scope: TransferUpdateScope) {
        let saved = Log.store.perform("Saving a transfer", errorMessage: &errorMessage) {
            try transaction.update(with: draftToSave, scope: scope, in: context)
        }
        if saved {
            dismiss()
        }
    }
}
