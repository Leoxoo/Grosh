import SwiftData
import SwiftUI

/// Adds a wallet (asking for the money it holds now, its Starting balance) or edits one.
struct WalletEditor: View {
    static let symbolChoices = [
        Wallet.defaultSymbolName, "creditcard.fill", "banknote.fill", "building.columns.fill",
        "dollarsign.circle.fill", "bitcoinsign.circle.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill",
        "briefcase.fill", "house.fill", "car.fill", "cart.fill",
        "bag.fill", "gift.fill", "airplane", "graduationcap.fill",
        "heart.fill", "star.fill", "lock.fill", "archivebox.fill",
        "person.fill", "person.2.fill", "globe.americas.fill", "leaf.fill",
    ]

    let mode: EditorMode<Wallet>

    @Environment(\.today) private var today
    @AppStorage(AppSettings.currencyCodeKey) private var currencyCode = AppSettings.currencyCodeDefault

    var body: some View {
        MadeOnce {
            (draft: mode.editing.map { WalletDraft($0) } ?? WalletDraft(currencyCode: currencyCode), startingDay: today)
        } content: { start in
            WalletForm(mode: mode, startingDraft: start.draft, startingDay: start.startingDay)
        }
    }
}

/// The form behind ``WalletEditor``, holding the draft from the moment the sheet opens.
private struct WalletForm: View {
    let mode: EditorMode<Wallet>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    @State private var draft: WalletDraft
    @State private var keypad = KeypadTarget()
    @FocusState private var isNameFocused: Bool
    @State private var startingDay: CalendarDay
    private var saver = SheetSaver(Strings.Wallets.couldntSave)
    @State private var isAdjustingBalance = false
    /// The wallet waiting for the user to confirm deleting it.
    @State private var deleting: Wallet?

    init(mode: EditorMode<Wallet>, startingDraft: WalletDraft, startingDay: CalendarDay) {
        self.mode = mode
        _draft = State(initialValue: startingDraft)
        _startingDay = State(initialValue: startingDay)
    }

    var body: some View {
        let check = draft.check
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SymbolCircle(symbolName: draft.symbolName, color: draft.color, size: 40)
                        TextField(Strings.Common.name, text: $draft.name)
                            .focused($isNameFocused)
                    }
                    Toggle(Strings.Wallets.includeInTotal, isOn: $draft.includeInTotal)
                } footer: {
                    if let problem = check.shownProblem {
                        Text(problem.localizedDescription)
                            .foregroundStyle(.invalid)
                    } else {
                        Text(Strings.Wallets.includeFooter)
                    }
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
                                saver.save("Changing a wallet") { try wallet.unarchive(today: today) }
                            }
                        } else {
                            Button(Strings.Wallets.archiveWallet, systemImage: "archivebox") {
                                saver.save("Changing a wallet") { try wallet.archive(today: today) }
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
            .keypad(keypad)
            .onChange(of: isNameFocused) {
                if isNameFocused {
                    keypad.hide()
                }
            }
            .navigationTitle(mode.isAdding ? Strings.Wallets.addWallet : Strings.Wallets.editWallet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isAdding ? Strings.Common.add : Strings.Common.save, action: save)
                        .disabled(!check.passes)
                }
            }
            .failureAlert(saver)
            .walletDeleteDialog($deleting) { dismiss() }
            .sheet(isPresented: $isAdjustingBalance) {
                AdjustBalanceEditor(viewedWallet: mode.editing)
            }
        }
    }

    private var startingBalanceSection: some View {
        Section {
            AmountRow(
                Strings.Wallets.currentBalance, field: "currentBalance", entry: $draft.startingBalanceEntry,
                currencyCode: draft.currencyCode,
                tint: (draft.startingBalance?.direction ?? .neither).tint, font: .body
            )
            DayStepper(title: Strings.Common.date, day: $startingDay)
        } header: {
            Text(Strings.Wallets.startingBalance)
        } footer: {
            Text(Strings.Wallets.startingBalanceFooter)
        }
    }

    private func save() {
        saver.save("Changing a wallet") {
            switch mode {
            case .add:
                try Wallet.create(draft, startingOn: startingDay, in: context)
            case .edit(let wallet):
                try wallet.update(with: draft)
            }
        }
    }
}
