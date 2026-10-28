import SwiftData
import SwiftUI

/// Adds a wallet (asking for the money it holds now, its Starting balance) or edits one.
struct WalletEditor: View {
    static let symbolChoices = [
        "wallet.bifold.fill", "creditcard.fill", "banknote.fill", "building.columns.fill",
        "dollarsign.circle.fill", "bitcoinsign.circle.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill",
        "briefcase.fill", "house.fill", "car.fill", "cart.fill",
        "bag.fill", "gift.fill", "airplane", "graduationcap.fill",
        "heart.fill", "star.fill", "lock.fill", "archivebox.fill",
        "person.fill", "person.2.fill", "globe.americas.fill", "leaf.fill",
    ]

    let mode: EditorMode<Wallet>

    @Environment(\.today) private var today

    var body: some View {
        WalletForm(mode: mode, startingDay: today)
    }
}

/// The form behind ``WalletEditor``, holding the draft from the moment the sheet opens.
private struct WalletForm: View {
    let mode: EditorMode<Wallet>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    @State private var draft: WalletDraft
    @State private var startingAmountText = ""
    @State private var startingDay: CalendarDay
    @State private var errorMessage: String?
    @State private var isAdjustingBalance = false
    /// The wallet waiting for the user to confirm deleting it.
    @State private var deleting: Wallet?

    init(mode: EditorMode<Wallet>, startingDay: CalendarDay) {
        self.mode = mode
        _draft = State(initialValue: mode.editing.map { WalletDraft($0) } ?? WalletDraft())
        _startingDay = State(initialValue: startingDay)
    }

    /// The Starting balance typed so far; an empty field means $0.
    private var startingBalance: Money? {
        startingAmountText.trimmingCharacters(in: .whitespaces).isEmpty
            ? Money(cents: 0)
            : Money(typedAmount: startingAmountText)
    }

    private var canSave: Bool { (try? draft.validate()) != nil && (!mode.isAdding || startingBalance != nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SymbolCircle(symbolName: draft.symbolName, color: draft.color, size: 40)
                        TextField(Strings.Common.name, text: $draft.name)
                    }
                    Toggle(Strings.Wallets.includeInTotal, isOn: $draft.includeInTotal)
                } footer: {
                    Text(Strings.Wallets.includeFooter)
                }

                if mode.isAdding {
                    startingBalanceSection
                }

                Section(Strings.Common.icon) {
                    SymbolGrid(symbols: WalletEditor.symbolChoices, selection: $draft.symbolName, color: draft.color)
                }

                Section(Strings.Common.color) {
                    PaletteColorGrid(selection: $draft.color)
                }

                if let wallet = mode.editing, !wallet.isArchived {
                    Section {
                        Button(Strings.BalanceAdjustment.adjustBalance, systemImage: "plusminus") { isAdjustingBalance = true }
                    } footer: {
                        Text(Strings.Wallets.adjustBalanceFooter)
                    }
                }

                if let wallet = mode.editing {
                    Section {
                        if wallet.isArchived {
                            Button(Strings.Wallets.unarchiveWallet, systemImage: "tray.and.arrow.up") {
                                perform { try wallet.unarchive(today: today) }
                            }
                        } else {
                            Button(Strings.Wallets.archiveWallet, systemImage: "archivebox") {
                                perform { try wallet.archive(today: today) }
                            }
                        }
                    } footer: {
                        Text(Strings.Wallets.archivedFooter)
                    }

                    Section {
                        Button(Strings.Wallets.deleteWallet, systemImage: "trash", role: .destructive) { deleting = wallet }
                            .foregroundStyle(.destructive)
                    } footer: {
                        Text(Strings.Wallets.deletingFooter(RecentlyDeleted.keptDays))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.isAdding ? Strings.Wallets.addWallet : Strings.Wallets.editWallet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isAdding ? Strings.Common.add : Strings.Common.save, action: save)
                        .disabled(!canSave)
                }
            }
            .errorAlert(Strings.Wallets.couldntSave, message: $errorMessage)
            .walletDeleteDialog($deleting) { dismiss() }
            .sheet(isPresented: $isAdjustingBalance) {
                AdjustBalanceEditor(viewedWallet: mode.editing)
            }
        }
    }

    private var startingBalanceSection: some View {
        Section {
            TextField(Strings.Wallets.currentBalance, text: $startingAmountText, prompt: Text(Money(cents: 0).formatted()))
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            DayStepper(title: Strings.Common.date, day: $startingDay)
        } header: {
            Text(Strings.Wallets.startingBalance)
        } footer: {
            if startingBalance == nil {
                Text(Strings.Wallets.amountExample)
                    .foregroundStyle(.invalid)
            } else {
                Text(Strings.Wallets.startingBalanceFooter)
            }
        }
    }

    private func save() {
        perform {
            switch mode {
            case .add:
                try Wallet.create(draft, startingBalance: startingBalance ?? Money(cents: 0), on: startingDay, in: context)
            case .edit(let wallet):
                try wallet.update(with: draft)
            }
        }
    }

    /// Runs a change and closes the sheet, or shows why the change was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            dismiss()
        } catch {
            Log.store.failed("Changing a wallet", error)
            errorMessage = error.localizedDescription
        }
    }
}
