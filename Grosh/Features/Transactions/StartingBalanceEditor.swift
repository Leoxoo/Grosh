import SwiftData
import SwiftUI

/// Edits a wallet's Starting balance: the money it held when it was added (below zero for a wallet that started
/// in debt), its date and note. It stays under the Starting balance category and excluded from report.
struct StartingBalanceEditor: View {
    private enum Field: Hashable {
        case amount, note
    }

    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: StartingBalanceDraft
    @State private var entry: AmountEntry
    @State private var isKeypadShown = true
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    init(transaction: Transaction) {
        self.transaction = transaction
        let draft = StartingBalanceDraft(editing: transaction)
        _draft = State(initialValue: draft)
        _entry = State(initialValue: AmountEntry(cents: draft.amount.cents))
    }

    private var currencyCode: String { transaction.amount.currencyCode }

    /// The draft with the amount the keypad comes to, or `nil` while the keypad shows an error.
    private var draftToSave: StartingBalanceDraft? {
        guard let cents = entry.cents else { return nil }
        var result = draft
        result.amount = Money(cents: cents, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let wallet = transaction.wallet {
                        LabeledContent("Wallet") {
                            Label(wallet.name, systemImage: wallet.symbolName)
                        }
                    }
                    AmountRow(
                        title: "Amount",
                        entry: $entry,
                        currencyCode: currencyCode,
                        tint: Money(cents: entry.cents ?? 0).tint
                    ) {
                        focus = .amount
                        isKeypadShown.toggle()
                    }
                    .focused($focus, equals: .amount)
                    Button("Change Sign", systemImage: "plusminus", action: changeSign)
                        .disabled(entry.cents == nil)
                    DayStepper(title: "Date", day: $draft.day)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .focused($focus, equals: .note)
                } footer: {
                    Text("The money this wallet held when it was added, below zero if it started in debt. It is always excluded from report.")
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if isKeypadShown {
                    AmountKeypad(entry: $entry)
                        .background(.bar)
                }
            }
            .navigationTitle("Edit Starting Balance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draftToSave == nil)
                }
            }
            .defaultFocus($focus, .amount)
            .onChange(of: focus) {
                if focus == .note {
                    isKeypadShown = false
                }
            }
            .alert("Couldn't Save Starting Balance", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 640)
        #endif
    }

    /// Turns a balance above zero into a debt of the same size, and back.
    private func changeSign() {
        guard let cents = entry.cents else { return }
        entry = AmountEntry(cents: -cents)
    }

    private func save() {
        guard let draftToSave else { return }
        do {
            try transaction.update(with: draftToSave)
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
