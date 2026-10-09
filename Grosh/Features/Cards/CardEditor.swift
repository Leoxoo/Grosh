import SwiftData
import SwiftUI

/// Adds a Card or edits one. Editing also archives, merges or deletes it.
struct CardEditor: View {
    enum Mode: Identifiable {
        case add
        case edit(Card)

        var id: AnyHashable {
            switch self {
            case .add: "add"
            case .edit(let card): card.persistentModelID
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(Wallet.unarchived) private var wallets: [Wallet]

    @State private var details: CardDetails
    /// Whether a Credit card has a statement date. The day is remembered while the user flips the kind back and forth.
    @State private var hasStatementDate: Bool
    @State private var statementDay: Int
    @State private var isMerging = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        let details = switch mode {
        case .add: CardDetails(name: "", kind: .credit, payingWallet: nil)
        case .edit(let card): CardDetails(card)
        }
        _details = State(initialValue: details)
        _hasStatementDate = State(initialValue: details.statementDay != nil)
        _statementDay = State(initialValue: details.statementDay ?? 1)
    }

    private var isAdding: Bool {
        if case .add = mode { true } else { false }
    }

    /// The Card being edited, until it is merged away or deleted (the sheet may draw once more while closing).
    private var editedCard: Card? {
        guard case .edit(let card) = mode, card.modelContext != nil, !card.isDeleted else { return nil }
        return card
    }

    /// What will be saved: the statement date only counts for a Credit card.
    private var detailsToSave: CardDetails {
        var result = details
        result.statementDay = details.kind == .credit && hasStatementDate ? statementDay : nil
        return result
    }

    private var validationError: CardRuleError? {
        do {
            try detailsToSave.validate()
            return nil
        } catch {
            return error as? CardRuleError
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SymbolCircle(symbolName: "creditcard.fill", color: details.color, size: 40)
                        TextField("Name", text: $details.name)
                    }
                    Picker("Kind", selection: $details.kind) {
                        ForEach(CardKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    WalletPicker(title: "Paying wallet", selection: $details.payingWallet)
                    TextField("Last 4 digits (optional)", text: lastFourDigits)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    if wallets.isEmpty && details.payingWallet == nil {
                        Text("Add a wallet first. A Card is paid from a wallet and only offered on its transactions.")
                    } else if let validationError, validationError != .missingName {
                        Text(validationError.localizedDescription)
                            .foregroundStyle(.red)
                    } else {
                        Text("A Card is only a label: it never changes any balance. It is offered on its paying wallet's transactions.")
                    }
                }

                if details.kind == .credit {
                    statementSection
                }

                Section("Color") {
                    PaletteColorGrid(selection: $details.color)
                }

                if let card = editedCard {
                    manageSection(card)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isAdding ? "Add Card" : "Edit Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Save", action: save)
                        .disabled(validationError != nil)
                }
            }
            .onAppear {
                if details.payingWallet == nil {
                    details.payingWallet = wallets.first
                }
            }
            .sheet(isPresented: $isMerging) {
                if let card = editedCard {
                    CardMergeView(source: card) { dismiss() }
                }
            }
            .alert("Couldn't Save Card", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// The last 4 digits field, which keeps only up to four digits as the user types.
    private var lastFourDigits: Binding<String> {
        Binding(
            get: { details.lastFourDigits ?? "" },
            set: { details.lastFourDigits = String($0.filter { ("0"..."9").contains($0) }.prefix(4)) }
        )
    }

    private var statementSection: some View {
        Section {
            Toggle("Statement date", isOn: $hasStatementDate)
            if hasStatementDate {
                Picker("Closes on the", selection: $statementDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text(Card.ordinalDay(day)).tag(day)
                    }
                }
            }
        } footer: {
            if hasStatementDate {
                Text("The statement closes on this day each month, or on the month's last day when the month is shorter.")
            } else {
                Text("Add the day this card's statement closes to see its transactions by statement period.")
            }
        }
    }

    @ViewBuilder
    private func manageSection(_ card: Card) -> some View {
        Section {
            if card.isArchived {
                Button("Unarchive Card", systemImage: "tray.and.arrow.up") {
                    card.unarchive()
                    dismiss()
                }
            } else {
                Button("Archive Card", systemImage: "archivebox") {
                    card.archive()
                    dismiss()
                }
            }
            Button("Merge into Another Card…", systemImage: "arrow.triangle.merge") {
                isMerging = true
            }
            if !card.hasTransactions {
                Button("Delete Card", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog("Delete “\(card.name)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Card", role: .destructive) { delete(card) }
                }
            }
        } footer: {
            if card.hasTransactions {
                Text("An archived Card leaves the pickers but stays on its transactions. To remove this Card, merge it into another one: its transactions move there.")
            } else {
                Text("An archived Card leaves the pickers but stays on its transactions.")
            }
        }
    }

    private func save() {
        do {
            switch mode {
            case .add:
                try Card.create(detailsToSave, in: context)
            case .edit(let card):
                try card.update(with: detailsToSave)
            }
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ card: Card) {
        do {
            try card.delete(in: context)
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension CardRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "Give the Card a name.")
        case .missingPayingWallet: String(localized: "Choose the wallet this Card is paid from.")
        case .statementDateRequiresCredit: String(localized: "Only Credit cards have a statement date.")
        case .statementDayOutOfRange: String(localized: "A statement date is a day from 1 to 31.")
        case .invalidLastFourDigits: String(localized: "Enter all 4 last digits, or leave them blank.")
        case .mergeIntoItself: String(localized: "Choose another Card to merge into.")
        case .hasTransactions: String(localized: "This Card paid for transactions. Merge it into another Card to remove it.")
        }
    }
}

/// The palette as a grid of color swatches.
private struct PaletteColorGrid: View {
    @Binding var selection: PaletteColor

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 12)], spacing: 12) {
            ForEach(PaletteColor.allCases, id: \.self) { choice in
                Button {
                    selection = choice
                } label: {
                    Circle()
                        .fill(choice.color.gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if choice == selection {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.rawValue.capitalized)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
