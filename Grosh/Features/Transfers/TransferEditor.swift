import SwiftData
import SwiftUI

/// The Transfer sheet: moves money from one of the user's wallets to another, recorded as an Outgoing transfer
/// and an Incoming transfer linked to each other.
struct TransferEditor: View {
    /// The wallet the Transactions tab is showing, which the transfer starts from.
    var viewedWallet: Wallet?

    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    var body: some View {
        MadeOnce {
            TransactionDefaults.suggestTransfer(on: today, viewing: viewedWallet, in: context)
        } content: { draft in
            TransferForm(startingDraft: draft)
        }
    }
}

/// The form behind ``TransferEditor``, holding the draft from the moment the sheet opens.
private struct TransferForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today
    /// What the pickers' balances add up.
    @NotDeletedTransactions private var transactions: [Transaction]

    @State private var draft: TransferDraft
    @State private var entry = AmountEntry(cents: 0)
    @State private var errorMessage: String?

    init(startingDraft: TransferDraft) {
        _draft = State(initialValue: startingDraft)
    }

    private var currencyCode: String { draft.from.currencyCodeOrDefault }

    private var draftToSave: TransferDraft { draft.withAmount(of: entry, in: currencyCode) }

    var body: some View {
        // Always today's balances, whatever the Date: a transfer dated later doesn't move them today.
        let balances = WalletBalances($transactions, asOf: today)
        let draftToSave = self.draftToSave
        KeypadSheet(title: Text(Strings.Transfers.transfer), entry: $entry, canSave: draftToSave.canSave, save: save) { fields in
            Section {
                WalletPicker(title: Strings.Common.from, selection: $draft.from, balances: balances)
                WalletPicker(title: Strings.Common.to, selection: $draft.to, balances: balances)
                fields.amountRow(Strings.Common.amount, currencyCode: currencyCode)
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                if let problem = draftToSave.shownProblem {
                    Text(problem.localizedDescription)
                } else {
                    Text(Strings.Transfers.footer)
                }
            }
        }
        .errorAlert(Strings.Transfers.couldntSave, message: $errorMessage)
    }

    private func save() {
        if Log.store.perform("Saving a transfer", errorMessage: &errorMessage, { try Transfer.create(draftToSave, in: context) }) {
            dismiss()
        }
    }
}

#Preview {
    TransferEditor()
        .modelContainer(try! StoreOpening.open(inMemory: true))
}
