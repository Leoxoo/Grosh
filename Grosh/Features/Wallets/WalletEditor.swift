import SwiftData
import SwiftUI

/// Adds a wallet (asking for the money it holds now, its Starting balance) or edits one.
struct WalletEditor: View {
    enum Mode: Identifiable {
        case add
        case edit(Wallet)

        var id: AnyHashable {
            switch self {
            case .add: "add"
            case .edit(let wallet): wallet.persistentModelID
            }
        }
    }

    static let symbolChoices = [
        "wallet.bifold.fill", "creditcard.fill", "banknote.fill", "building.columns.fill",
        "dollarsign.circle.fill", "bitcoinsign.circle.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill",
        "briefcase.fill", "house.fill", "car.fill", "cart.fill",
        "bag.fill", "gift.fill", "airplane", "graduationcap.fill",
        "heart.fill", "star.fill", "lock.fill", "archivebox.fill",
        "person.fill", "person.2.fill", "globe.americas.fill", "leaf.fill",
    ]

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var symbolName: String
    @State private var color: PaletteColor
    @State private var includeInTotal: Bool
    @State private var startingAmountText = ""
    @State private var startingDate = CalendarDay.today.date()
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _symbolName = State(initialValue: "wallet.bifold.fill")
            _color = State(initialValue: .green)
            _includeInTotal = State(initialValue: true)
        case .edit(let wallet):
            _name = State(initialValue: wallet.name)
            _symbolName = State(initialValue: wallet.symbolName)
            _color = State(initialValue: wallet.color)
            _includeInTotal = State(initialValue: wallet.includeInTotal)
        }
    }

    private var isAdding: Bool {
        if case .add = mode { true } else { false }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The Starting balance typed so far; an empty field means $0.
    private var startingBalance: Money? {
        startingAmountText.trimmingCharacters(in: .whitespaces).isEmpty
            ? Money(cents: 0)
            : Money(typedAmount: startingAmountText)
    }

    private var canSave: Bool { !trimmedName.isEmpty && (!isAdding || startingBalance != nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SymbolCircle(symbolName: symbolName, color: color, size: 40)
                        TextField("Name", text: $name)
                    }
                    Toggle("Include in Total", isOn: $includeInTotal)
                } footer: {
                    Text("The Total on Home adds up the wallets that are included.")
                }

                if isAdding {
                    startingBalanceSection
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
                        ForEach(Self.symbolChoices, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                SymbolCircle(symbolName: symbol, color: symbol == symbolName ? color : .gray, size: 36)
                                    .opacity(symbol == symbolName ? 1 : 0.5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(symbol == symbolName ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 12)], spacing: 12) {
                        ForEach(PaletteColor.allCases, id: \.self) { choice in
                            Button {
                                color = choice
                            } label: {
                                Circle()
                                    .fill(choice.color.gradient)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if choice == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.rawValue.capitalized)
                            .accessibilityAddTraits(choice == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                if case .edit(let wallet) = mode {
                    Section {
                        if wallet.isArchived {
                            Button("Unarchive Wallet", systemImage: "tray.and.arrow.up") {
                                try? wallet.unarchive(in: context)
                                dismiss()
                            }
                        } else {
                            Button("Archive Wallet", systemImage: "archivebox") {
                                wallet.archive()
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("An archived wallet leaves the Total and the pickers but keeps its transactions.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isAdding ? "Add Wallet" : "Edit Wallet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Couldn't Save Wallet", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var startingBalanceSection: some View {
        Section {
            TextField("Current balance", text: $startingAmountText, prompt: Text(Money(cents: 0).formatted()))
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            DatePicker("Date", selection: $startingDate, displayedComponents: .date)
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
        do {
            switch mode {
            case .add:
                try Wallet.create(
                    name: trimmedName,
                    symbolName: symbolName,
                    color: color,
                    includeInTotal: includeInTotal,
                    startingBalance: startingBalance ?? Money(cents: 0),
                    on: CalendarDay(startingDate),
                    in: context
                )
            case .edit(let wallet):
                wallet.name = trimmedName
                wallet.symbolName = symbolName
                wallet.colorName = color.rawValue
                wallet.includeInTotal = includeInTotal
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
