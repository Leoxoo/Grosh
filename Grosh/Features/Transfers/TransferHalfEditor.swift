import SwiftData
import SwiftUI

/// Edits one half of a transfer: its amount, date and note. Its wallets stay as the transfer recorded them. When
/// the amount or date changes, Save asks whether to update the other half too, or only this one (as when a fee
/// was taken).
struct TransferHalfEditor: View {
    let transaction: Transaction

    @Environment(\.modelContext) private var context

    @State private var draft: TransferHalfDraft
    @State private var isAskingScope = false

    init(transaction: Transaction) {
        self.transaction = transaction
        _draft = State(initialValue: TransferHalfDraft(editing: transaction))
    }

    var body: some View {
        KeypadSheet(
            title: Text(transaction.categoryName), entry: $draft.entry, canSave: draft.canSave,
            saving: "Saving a transfer", failureTitle: Strings.Transfers.couldntSave, saveThen: saveOrAsk
        ) { fields in
            Section {
                wallets
                fields.amountRow(
                    Strings.Common.amount, currencyCode: draft.currencyCode,
                    tint: MoneyDirection(category: transaction.category).tint
                )
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                Text(Strings.Transfers.halfFooter)
            }
            .confirmationDialog(
                Strings.Transfers.updateOtherHalfQuestion,
                isPresented: $isAskingScope,
                titleVisibility: .visible
            ) {
                Button(Strings.Transfers.updateBoth) { save(.bothHalves, with: fields.saver) }
                Button(Strings.Common.onlyThisOne) { save(.onlyThisOne, with: fields.saver) }
                Button(Strings.Common.cancel, role: .cancel) {}
            } message: {
                Text(Strings.Transfers.onlyThisOneFooter)
            }
        }
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
    private func saveOrAsk() throws -> AfterSaving {
        if try transaction.offersToUpdateOtherHalf(with: draft, in: context) {
            isAskingScope = true
            return .stayOpen
        }
        try transaction.update(with: draft, scope: .onlyThisOne, in: context)
        return .close
    }

    private func save(_ scope: TransferUpdateScope, with saver: SheetSaver) {
        saver.save("Saving a transfer") {
            try transaction.update(with: draft, scope: scope, in: context)
        }
    }
}
