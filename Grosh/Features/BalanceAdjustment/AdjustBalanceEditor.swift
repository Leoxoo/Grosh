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
    @Environment(\.today) private var today

    var body: some View {
        if let draft = startingDraft {
            AdjustBalanceForm(startingDraft: draft)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    Strings.BalanceAdjustment.cantAdjust,
                    systemImage: "exclamationmark.triangle",
                    description: Text(Strings.BalanceAdjustment.categoriesMissing)
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.Common.cancel) { dismiss() }
                    }
                }
            }
        }
    }

    private var startingDraft: BalanceAdjustmentDraft? {
        Log.store.attempt("Suggesting a balance adjustment") {
            try TransactionDefaults.suggestBalanceAdjustment(on: today, viewing: viewedWallet, in: context)
        }
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
            title: Text(Strings.BalanceAdjustment.adjustBalance),
            entry: $draft.realBalanceEntry,
            canSave: draft.canSave,
            save: save,
            macHeight: (640, 720)
        ) { fields in
            balanceSection(fields)
            reasonSection(fields)
        }
        .errorAlert(Strings.BalanceAdjustment.couldntAdjust, message: $errorMessage)
    }

    private func balanceSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            WalletPicker(title: Strings.Common.wallet, selection: $draft.wallet)
            DayStepper(title: Strings.Common.date, day: $draft.day)
            if let recorded = draft.recordedBalance {
                LabeledContent(Strings.BalanceAdjustment.recordedBalance) {
                    AmountText(amount: recorded, showsColor: false)
                }
            }
            fields.amountRow(
                Strings.BalanceAdjustment.realBalance, currencyCode: draft.currencyCode, tint: Money(cents: draft.realBalance?.cents ?? 0).tint
            )
            ChangeSignButton(entry: $draft.realBalanceEntry)
        } footer: {
            if draft.wallet == nil {
                Text(Strings.Common.addWalletFirst)
            } else {
                Text(Strings.BalanceAdjustment.typeRealBalanceFooter)
            }
        }
    }

    private func reasonSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            LabeledContent(Strings.Common.difference) {
                AmountText(
                    amount: draft.difference ?? Money(cents: 0, currencyCode: draft.currencyCode),
                    showsPlusSign: true,
                    showsColor: false
                )
            }
            if let reasonType = draft.reasonType {
                CategoryPicker(title: Strings.BalanceAdjustment.reason, type: reasonType, selection: $draft.category)
            }
            fields.noteField($draft.note)
            Toggle(Strings.Common.excludeFromReport, isOn: $draft.isExcludedFromReport)
        } footer: {
            if draft.reasonType == nil {
                Text(Strings.BalanceAdjustment.alreadyMatchesFooter)
            } else {
                Text(Strings.BalanceAdjustment.reasonFooter)
            }
        }
    }

    private func save() {
        do {
            try Transaction.adjustBalance(draft, in: context)
            dismiss()
        } catch {
            Log.store.failed("Adjusting a balance", error)
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AdjustBalanceEditor()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
