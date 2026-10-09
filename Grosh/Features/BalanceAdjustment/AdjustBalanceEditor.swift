import SwiftData
import SwiftUI

/// Adjust Balance: the user types a wallet's real balance on a day, and the difference from what its transactions
/// add up to is recorded as one balance adjustment, filed under a reason.
struct AdjustBalanceEditor: View {
    /// The wallet to adjust, or `nil` to start from the suggested one.
    let wallet: Wallet?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        if let draft = startingDraft {
            AdjustBalanceForm(startingDraft: draft)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Can't Adjust Balance",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The Other Income and Other Expense categories are missing.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var startingDraft: BalanceAdjustmentDraft? {
        let wallet = wallet ?? TransactionDefaults.suggest(on: .today, in: context).wallet
        return try? BalanceAdjustmentDraft(wallet: wallet, day: .today, in: context)
    }
}

/// The form behind ``AdjustBalanceEditor``, holding the draft from the moment the sheet opens.
private struct AdjustBalanceForm: View {
    private enum Field: Hashable {
        case amount, note
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: BalanceAdjustmentDraft
    /// The real balance being typed. It starts at the recorded balance; the first digit replaces it.
    @State private var entry: AmountEntry
    @State private var isKeypadShown = true
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    init(startingDraft: BalanceAdjustmentDraft) {
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: AmountEntry(cents: startingDraft.actualBalance.cents))
    }

    private var currencyCode: String { draft.wallet?.currencyCode ?? Money.defaultCurrencyCode }

    /// The draft with the real balance the keypad comes to, or `nil` while the keypad shows an error.
    private var draftToSave: BalanceAdjustmentDraft? {
        guard let cents = entry.cents else { return nil }
        var result = draft
        result.actualBalance = Money(cents: cents, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                balanceSection
                reasonSection
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if isKeypadShown {
                    AmountKeypad(entry: $entry)
                        .background(.bar)
                }
            }
            .navigationTitle("Adjust Balance")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draftToSave?.canSave != true)
                }
            }
            .defaultFocus($focus, .amount)
            .onChange(of: focus) {
                if focus == .note {
                    isKeypadShown = false
                }
            }
            .onChange(of: draft.wallet) {
                // The real balance typed belonged to the other wallet: start again from this one's.
                entry = AmountEntry(cents: draft.recordedBalance?.cents ?? 0)
            }
            .errorAlert("Couldn't Adjust Balance", message: $errorMessage)
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 640, idealHeight: 720)
        #endif
    }

    private var balanceSection: some View {
        Section {
            WalletPicker(title: "Wallet", selection: $draft.wallet)
            DayStepper(title: "Date", day: $draft.day)
            if let recorded = draft.recordedBalance {
                LabeledContent("Recorded balance") {
                    AmountText(amount: recorded)
                }
            }
            AmountRow(
                title: "Actual balance",
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
        } footer: {
            if draft.wallet == nil {
                Text("Add a wallet first, in Account → Wallets.")
            } else {
                Text("Type what the wallet really holds on this date. The difference is recorded as one transaction.")
            }
        }
    }

    private var reasonSection: some View {
        Section {
            LabeledContent("Difference") {
                AmountText(amount: draftToSave?.difference ?? Money(cents: 0, currencyCode: currencyCode), showsPlusSign: true)
            }
            if let reasonType = draftToSave?.reasonType {
                CategoryPicker(title: "Reason", type: reasonType, selection: reason)
            }
            TextField("Note", text: $draft.note, axis: .vertical)
                .focused($focus, equals: .note)
            Toggle("Exclude from report", isOn: $draft.isExcludedFromReport)
        } footer: {
            if draftToSave?.reasonType == nil {
                Text("The recorded balance already matches. Type the real balance to adjust it.")
            } else {
                Text("The reason is any Income category when the balance goes up, or any Expense category when it goes down. It counts in reports unless excluded, and never needs a Card.")
            }
        }
    }

    /// The reason as the picker shows it: the one that applies to the difference typed so far.
    private var reason: Binding<Category?> {
        Binding(
            get: { draftToSave?.category },
            set: { draft.category = $0 }
        )
    }

    /// Turns a balance above zero into a debt of the same size, and back.
    private func changeSign() {
        guard let cents = entry.cents else { return }
        entry = AmountEntry(cents: -cents)
    }

    private func save() {
        guard let draftToSave else { return }
        do {
            try Transaction.adjustBalance(draftToSave, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AdjustBalanceEditor(wallet: nil)
        .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
