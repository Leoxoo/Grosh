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
        TransferForm(startingDraft: TransactionDefaults.suggestTransfer(on: today, viewing: viewedWallet, in: context))
    }
}

/// The form behind ``TransferEditor``, holding the draft from the moment the sheet opens.
private struct TransferForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    @State private var draft: TransferDraft
    @State private var entry = AmountEntry(cents: 0)
    @State private var errorMessage: String?

    init(startingDraft: TransferDraft) {
        _draft = State(initialValue: startingDraft)
    }

    private var currencyCode: String { draft.from?.currencyCode ?? Money.defaultCurrencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: TransferDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        KeypadSheet(title: Text(Strings.Transfers.transfer), entry: $entry, canSave: draftToSave.canSave, save: save) { fields in
            Section {
                // Always today's balances, whatever the Date: a transfer dated later doesn't move them today.
                WalletPicker(title: Strings.Common.from, selection: $draft.from, balancesAsOf: today)
                WalletPicker(title: Strings.Common.to, selection: $draft.to, balancesAsOf: today)
                fields.amountRow(Strings.Common.amount, currencyCode: currencyCode)
                DayStepper(title: Strings.Common.date, day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                if draft.from == nil || draft.to == nil {
                    Text(Strings.Transfers.twoWalletsNeeded)
                } else if draft.from == draft.to {
                    Text(Strings.Common.chooseTwoDifferentWallets)
                } else {
                    Text(Strings.Transfers.footer)
                }
            }
        }
        .errorAlert(Strings.Transfers.couldntSave, message: $errorMessage)
    }

    private func save() {
        do {
            try Transfer.create(draftToSave, in: context)
            dismiss()
        } catch {
            Log.store.failed("Saving a transfer", error)
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TransferEditor()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
