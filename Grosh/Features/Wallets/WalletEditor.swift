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
        _draft = State(initialValue: mode.editing.map(WalletDraft.init) ?? WalletDraft())
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
                        TextField("Name", text: $draft.name)
                    }
                    Toggle("Include in Total", isOn: $draft.includeInTotal)
                } footer: {
                    Text("The Total on Home adds up the wallets that are included.")
                }

                if mode.isAdding {
                    startingBalanceSection
                }

                Section("Icon") {
                    SymbolGrid(symbols: WalletEditor.symbolChoices, selection: $draft.symbolName, color: draft.color)
                }

                Section("Color") {
                    PaletteColorGrid(selection: $draft.color)
                }

                if let wallet = mode.editing, !wallet.isArchived {
                    Section {
                        Button("Adjust Balance", systemImage: "plusminus") { isAdjustingBalance = true }
                    } footer: {
                        Text("Type what the wallet really holds; the difference is recorded as one transaction.")
                    }
                }

                if let wallet = mode.editing {
                    Section {
                        if wallet.isArchived {
                            Button("Unarchive Wallet", systemImage: "tray.and.arrow.up") {
                                perform { try wallet.unarchive(today: today) }
                            }
                        } else {
                            Button("Archive Wallet", systemImage: "archivebox") {
                                perform { try wallet.archive(today: today) }
                            }
                        }
                    } footer: {
                        Text("An archived wallet leaves the Total and the pickers but keeps its transactions. Its Recurring transactions pause until it is unarchived.")
                    }

                    Section {
                        Button("Delete Wallet", systemImage: "trash", role: .destructive) { deleting = wallet }
                            .foregroundStyle(.red)
                    } footer: {
                        Text("Deleting moves the wallet, its transactions and its Recurring transactions to Recently Deleted for \(RecentlyDeleted.keptDays) days.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.isAdding ? "Add Wallet" : "Edit Wallet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isAdding ? "Add" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
            .errorAlert("Couldn't Save Wallet", message: $errorMessage)
            .walletDeleteDialog($deleting) { dismiss() }
            .sheet(isPresented: $isAdjustingBalance) {
                AdjustBalanceEditor(viewedWallet: mode.editing)
            }
        }
    }

    private var startingBalanceSection: some View {
        Section {
            TextField("Current balance", text: $startingAmountText, prompt: Text(Money(cents: 0).formatted()))
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            DayStepper(title: "Date", day: $startingDay)
        } header: {
            Text("Starting balance")
        } footer: {
            if startingBalance == nil {
                Text("Enter an amount such as 1,250.00.")
                    .foregroundStyle(.red)
            } else {
                Text("The money this wallet holds now. It becomes the wallet's first transaction and is excluded from report.")
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
