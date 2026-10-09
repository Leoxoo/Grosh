import SwiftData
import SwiftUI

/// Edits one half of a transfer: its amount, date and note. Its wallets stay as the transfer recorded them. When
/// the amount or date changes, Save asks whether to update the other half too, or only this one (as when a fee
/// was taken).
struct TransferHalfEditor: View {
    private enum Field: Hashable {
        case amount, note
    }

    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: TransferHalfDraft
    @State private var entry: AmountEntry
    @State private var isKeypadShown = true
    @State private var isAskingScope = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    init(transaction: Transaction) {
        self.transaction = transaction
        let draft = TransferHalfDraft(editing: transaction)
        _draft = State(initialValue: draft)
        _entry = State(initialValue: AmountEntry(cents: draft.amount.cents))
    }

    private var currencyCode: String { transaction.amount.currencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: TransferHalfDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    wallets
                    AmountRow(
                        title: "Amount",
                        entry: $entry,
                        currencyCode: currencyCode,
                        tint: Money(cents: transaction.category?.sign ?? 0).tint
                    ) {
                        focus = .amount
                        isKeypadShown.toggle()
                    }
                    .focused($focus, equals: .amount)
                    DayStepper(title: "Date", day: $draft.day)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .focused($focus, equals: .note)
                } footer: {
                    Text("Changing the amount or date asks whether to change the other half of the transfer too.")
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if isKeypadShown {
                    AmountKeypad(entry: $entry)
                        .background(.bar)
                }
            }
            .navigationTitle(transaction.categoryName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: confirmSave)
                        .disabled(!draftToSave.canSave)
                }
            }
            .defaultFocus($focus, .amount)
            .onChange(of: focus) {
                if focus == .note {
                    isKeypadShown = false
                }
            }
            .confirmationDialog(
                "Update the other half of the transfer too?",
                isPresented: $isAskingScope,
                titleVisibility: .visible
            ) {
                Button("Update Both") { save(.bothHalves) }
                Button("Only This One") { save(.onlyThisOne) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only This One leaves the two halves different, as when a fee was taken.")
            }
            .errorAlert("Couldn't Save Transfer", message: $errorMessage)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 640)
        #endif
    }

    /// Where the money left and where it went: this half's wallet and, while it is there, the other half's.
    @ViewBuilder
    private var wallets: some View {
        let wallets = try? transaction.transferWallets(in: context)
        WalletLabel(title: "From", wallet: wallets?.from)
        WalletLabel(title: "To", wallet: wallets?.to)
    }

    /// Saves straight away, or first asks whether to update both halves when the amount or date changed.
    private func confirmSave() {
        do {
            if try transaction.offersToUpdateOtherHalf(with: draftToSave, in: context) {
                isAskingScope = true
            } else {
                save(.onlyThisOne)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ scope: TransferUpdateScope) {
        do {
            try transaction.update(with: draftToSave, scope: scope, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
