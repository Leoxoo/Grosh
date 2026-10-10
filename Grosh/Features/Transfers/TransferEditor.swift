import SwiftData
import SwiftUI

/// The Transfer sheet: moves money from one of the user's wallets to another, recorded as an Outgoing transfer
/// and an Incoming transfer linked to each other.
struct TransferEditor: View {
    /// The wallet the Transactions tab is showing, which the transfer starts from.
    var viewedWallet: Wallet?

    @Environment(\.modelContext) private var context

    var body: some View {
        TransferForm(startingDraft: TransactionDefaults.suggestTransfer(on: .today, viewing: viewedWallet, in: context))
    }
}

/// The form behind ``TransferEditor``, holding the draft from the moment the sheet opens.
private struct TransferForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

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
        KeypadSheet(title: Text("Transfer"), entry: $entry, canSave: draftToSave.canSave, save: save) { fields in
            Section {
                WalletPicker(title: "From", selection: $draft.from)
                WalletPicker(title: "To", selection: $draft.to)
                fields.amountRow("Amount", currencyCode: currencyCode)
                DayStepper(title: "Date", day: $draft.day)
                fields.noteField($draft.note)
            } footer: {
                if draft.from == nil || draft.to == nil {
                    Text("A transfer needs two wallets. Add another in Account → Wallets.")
                } else if draft.from == draft.to {
                    Text("Choose two different wallets.")
                } else {
                    Text("Recorded as an Outgoing transfer and an Incoming transfer, linked to each other. A transfer is never income or spending, and the Total doesn't change.")
                }
            }
        }
        .errorAlert("Couldn't Save Transfer", message: $errorMessage)
    }

    private func save() {
        do {
            try Transfer.create(draftToSave, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TransferEditor()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
