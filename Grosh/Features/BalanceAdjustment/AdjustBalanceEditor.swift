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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: BalanceAdjustmentDraft
    @State private var errorMessage: String?

    init(startingDraft: BalanceAdjustmentDraft) {
        _draft = State(initialValue: startingDraft)
    }

    var body: some View {
        KeypadSheet(
            title: Text("Adjust Balance"),
            entry: $draft.realBalanceEntry,
            canSave: draft.canSave,
            save: save,
            macHeight: (640, 720)
        ) { fields in
            balanceSection(fields)
            reasonSection(fields)
        }
        .errorAlert("Couldn't Adjust Balance", message: $errorMessage)
    }

    private func balanceSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            WalletPicker(title: "Wallet", selection: $draft.wallet)
            DayStepper(title: "Date", day: $draft.day)
            if let recorded = draft.recordedBalance {
                LabeledContent("Recorded balance") {
                    AmountText(amount: recorded)
                }
            }
            fields.amountRow(
                "Real balance", currencyCode: draft.currencyCode, tint: Money(cents: draft.realBalance?.cents ?? 0).tint
            )
            ChangeSignButton(entry: $draft.realBalanceEntry)
        } footer: {
            if draft.wallet == nil {
                Text("Add a wallet first, in Account → Wallets.")
            } else {
                Text("Type what the wallet really holds on this date. The difference is recorded as one transaction.")
            }
        }
    }

    private func reasonSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            LabeledContent("Difference") {
                AmountText(amount: draft.difference ?? Money(cents: 0, currencyCode: draft.currencyCode), showsPlusSign: true)
            }
            if let reasonType = draft.reasonType {
                CategoryPicker(title: "Reason", type: reasonType, selection: $draft.category)
            }
            fields.noteField($draft.note)
            Toggle("Exclude from report", isOn: $draft.isExcludedFromReport)
        } footer: {
            if draft.reasonType == nil {
                Text("The recorded balance already matches. Type the real balance to adjust it.")
            } else {
                Text("The reason is any Income category when the balance goes up, or any Expense category when it goes down. It counts in reports unless excluded, and never needs a Card.")
            }
        }
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
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
