import SwiftData
import SwiftUI

/// Adjust Balance: the user types a wallet's real balance on a day, and the difference from what its transactions
/// add up to is recorded as one balance adjustment, filed under a reason.
struct AdjustBalanceEditor: View {
    /// The wallet the screen it was opened from shows, which the adjustment starts in; `nil` (the Total) starts in
    /// the suggested one.
    var viewedWallet: Wallet?

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
        try? TransactionDefaults.suggestBalanceAdjustment(on: .today, viewing: viewedWallet, in: context)
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
    @State private var isKeypadShown = true
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    init(startingDraft: BalanceAdjustmentDraft) {
        _draft = State(initialValue: startingDraft)
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
                    AmountKeypad(entry: $draft.actualBalanceEntry)
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
                        .disabled(!draft.canSave)
                }
            }
            .defaultFocus($focus, .amount)
            .onChange(of: focus) {
                if focus == .note {
                    isKeypadShown = false
                }
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
                entry: $draft.actualBalanceEntry,
                currencyCode: draft.currencyCode,
                tint: Money(cents: draft.actualBalance?.cents ?? 0).tint
            ) {
                focus = .amount
                isKeypadShown.toggle()
            }
            .focused($focus, equals: .amount)
            Button("Change Sign", systemImage: "plusminus", action: changeSign)
                .disabled(draft.actualBalance == nil)
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
                AmountText(amount: draft.difference ?? Money(cents: 0, currencyCode: draft.currencyCode), showsPlusSign: true)
            }
            if let reasonType = draft.reasonType {
                CategoryPicker(title: "Reason", type: reasonType, selection: $draft.category)
            }
            TextField("Note", text: $draft.note, axis: .vertical)
                .focused($focus, equals: .note)
            Toggle("Exclude from report", isOn: $draft.isExcludedFromReport)
        } footer: {
            if draft.reasonType == nil {
                Text("The recorded balance already matches. Type the real balance to adjust it.")
            } else {
                Text("The reason is any Income category when the balance goes up, or any Expense category when it goes down. It counts in reports unless excluded, and never needs a Card.")
            }
        }
    }

    /// Turns a balance above zero into a debt of the same size, and back.
    private func changeSign() {
        guard let cents = draft.actualBalance?.cents else { return }
        draft.actualBalanceEntry = AmountEntry(cents: -cents)
    }

    private func save() {
        do {
            try Transaction.adjustBalance(draft, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AdjustBalanceEditor()
        .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
