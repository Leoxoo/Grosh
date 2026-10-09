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

    @State private var draft: CardDraft
    /// Whether a Credit card has a statement date. The day is remembered while the user flips the kind back and forth.
    @State private var hasStatementDate: Bool
    @State private var statementDay: Int
    @State private var isMerging = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        let draft = switch mode {
        case .add: CardDraft(name: "", kind: .credit, payingWallet: nil)
        case .edit(let card): CardDraft(card)
        }
        _draft = State(initialValue: draft)
        _hasStatementDate = State(initialValue: draft.statementDay != nil)
        _statementDay = State(initialValue: draft.statementDay ?? 1)
    }

    private var isAdding: Bool {
        if case .add = mode { true } else { false }
    }

    /// The Card being edited, until it is merged away or deleted (the sheet may draw once more while closing).
    private var editedCard: Card? {
        guard case .edit(let card) = mode, card.modelContext != nil, !card.isDeleted else { return nil }
        return card
    }

    /// A Card that paid for transactions keeps its paying wallet.
    private var isPayingWalletFixed: Bool { editedCard?.hasTransactions == true }

    /// What will be saved: the statement date only counts for a Credit card.
    private var draftToSave: CardDraft {
        var result = draft
        result.statementDay = draft.kind == .credit && hasStatementDate ? statementDay : nil
        return result
    }

    private var validationError: CardRuleError? {
        do {
            try draftToSave.validate()
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
                        SymbolCircle(symbolName: Card.symbolName, color: draft.color, size: 40)
                        TextField("Name", text: $draft.name)
                    }
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(CardKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    WalletPicker(title: "Paying wallet", selection: $draft.payingWallet)
                        .disabled(isPayingWalletFixed)
                    TextField("Last 4 digits (optional)", text: lastFourDigits)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    if wallets.isEmpty && draft.payingWallet == nil {
                        Text("Add a wallet first. A Card is paid from a wallet and only offered on its transactions.")
                    } else if isPayingWalletFixed {
                        Text(CardRuleError.payingWalletHasTransactions.localizedDescription)
                    } else if let validationError, validationError != .missingName {
                        Text(validationError.localizedDescription)
                            .foregroundStyle(.red)
                    } else {
                        Text("A Card is only a label: it never changes any balance. It is offered on its paying wallet's transactions.")
                    }
                }

                if draft.kind == .credit {
                    statementSection
                }

                Section("Color") {
                    PaletteColorGrid(selection: $draft.color)
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
                if draft.payingWallet == nil {
                    draft.payingWallet = wallets.first
                }
            }
            .sheet(isPresented: $isMerging) {
                if let card = editedCard {
                    CardMergeView(source: card) { dismiss() }
                }
            }
            .errorAlert("Couldn't Save Card", message: $errorMessage)
        }
    }

    /// The last 4 digits field, which keeps only up to four digits as the user types.
    private var lastFourDigits: Binding<String> {
        Binding(
            get: { draft.lastFourDigits ?? "" },
            set: { draft.lastFourDigits = String($0.filter { ("0"..."9").contains($0) }.prefix(4)) }
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
                try Card.create(draftToSave, in: context)
            case .edit(let card):
                try card.update(with: draftToSave)
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
