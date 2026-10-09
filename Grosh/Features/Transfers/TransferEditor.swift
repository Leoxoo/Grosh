import SwiftData
import SwiftUI

/// The Transfer sheet: moves money from one of the user's wallets to another, recorded as an Outgoing transfer
/// and an Incoming transfer linked to each other.
struct TransferEditor: View {
    /// The wallet the Transactions tab is showing, which the transfer starts from.
    var viewedWallet: Wallet?

    @Environment(\.modelContext) private var context

    var body: some View {
        TransferForm(startingDraft: TransactionDefaults.suggestTransfer(on: .today, from: viewedWallet, in: context))
    }
}

/// The form behind ``TransferEditor``, holding the draft from the moment the sheet opens.
private struct TransferForm: View {
    private enum Field: Hashable {
        case amount, note
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: TransferDraft
    @State private var entry = AmountEntry(cents: 0)
    @State private var isKeypadShown = true
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

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
        NavigationStack {
            Form {
                Section {
                    WalletPicker(title: "From", selection: $draft.from)
                    WalletPicker(title: "To", selection: $draft.to)
                    AmountRow(title: "Amount", entry: $entry, currencyCode: currencyCode) {
                        focus = .amount
                        isKeypadShown.toggle()
                    }
                    .focused($focus, equals: .amount)
                    DayStepper(title: "Date", day: $draft.day)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .focused($focus, equals: .note)
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
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if isKeypadShown {
                    AmountKeypad(entry: $entry)
                        .background(.bar)
                }
            }
            .navigationTitle("Transfer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draftToSave.canSave)
                }
            }
            .defaultFocus($focus, .amount)
            .onChange(of: focus) {
                if focus == .note {
                    isKeypadShown = false
                }
            }
            .errorAlert("Couldn't Save Transfer", message: $errorMessage)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 640)
        #endif
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
        .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
