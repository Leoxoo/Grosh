import SwiftData
import SwiftUI

/// Adds a Card or edits one. Editing also archives, merges or deletes it.
struct CardEditor: View {
    let mode: EditorMode<Card>

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

    init(mode: EditorMode<Card>) {
        self.mode = mode
        let draft = mode.editing.map { CardDraft($0) } ?? CardDraft(name: "", kind: .credit, payingWallet: nil)
        _draft = State(initialValue: draft)
        _hasStatementDate = State(initialValue: draft.statementDay != nil)
        _statementDay = State(initialValue: draft.statementDay ?? 1)
    }

    /// The Card being edited, until it is merged away or deleted (the sheet may draw once more while closing).
    private var editedCard: Card? {
        guard let card = mode.editing, card.modelContext != nil, !card.isDeleted else { return nil }
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
                        CardMark(image: draft.imageData.flatMap(CroppedPhoto.image(from:)), height: 26) {
                            SymbolCircle(symbolName: Card.symbolName, color: draft.color, size: 40)
                        }
                        TextField(Strings.Common.name, text: $draft.name)
                    }
                    Picker(Strings.Common.kind, selection: $draft.kind) {
                        ForEach(CardKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    WalletPicker(title: Strings.Cards.payingWallet, selection: $draft.payingWallet)
                        .disabled(isPayingWalletFixed)
                    TextField(Strings.Cards.lastFourDigits, text: lastFourDigits)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    PhotoField(shape: .creditCard, data: imageData)
                } footer: {
                    if wallets.isEmpty && draft.payingWallet == nil {
                        Text(Strings.Cards.addWalletFirstFooter)
                    } else if isPayingWalletFixed {
                        Text(CardRuleError.payingWalletHasTransactions.localizedDescription)
                    } else if let validationError, validationError != .missingName {
                        Text(validationError.localizedDescription)
                            .foregroundStyle(.invalid)
                    } else {
                        Text(Strings.Cards.onlyALabelFooter)
                    }
                }

                if draft.kind == .credit {
                    statementSection
                }

                Section {
                    PaletteColorGrid(selection: $draft.color)
                        .disabled(draft.imageData != nil)
                } header: {
                    Text(Strings.Common.color)
                } footer: {
                    if draft.imageData != nil {
                        Text(Strings.Cards.imageColorFooter)
                    }
                }

                if let card = editedCard {
                    manageSection(card)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode.isAdding ? Strings.Cards.addCard : Strings.Cards.editCard)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isAdding ? Strings.Common.add : Strings.Common.save, action: save)
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
            .errorAlert(Strings.Cards.couldntSave, message: $errorMessage)
        }
    }

    /// The Card's image, which also sets its color (``CardDraft/setImage(_:)``).
    private var imageData: Binding<Data?> {
        Binding(
            get: { draft.imageData },
            set: { draft.setImage($0) }
        )
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
            Toggle(Strings.Cards.statementDate, isOn: $hasStatementDate)
            if hasStatementDate {
                Picker(Strings.Cards.closesOnThe, selection: $statementDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text(Card.ordinalDay(day)).tag(day)
                    }
                }
            }
        } footer: {
            if hasStatementDate {
                Text(Strings.Cards.statementDayFooter)
            } else {
                Text(Strings.Cards.addStatementDayFooter)
            }
        }
    }

    @ViewBuilder
    private func manageSection(_ card: Card) -> some View {
        Section {
            if card.isArchived {
                Button(Strings.Cards.unarchiveCard, systemImage: "tray.and.arrow.up") {
                    perform { try card.unarchive() }
                }
            } else {
                Button(Strings.Cards.archiveCard, systemImage: "archivebox") {
                    perform { try card.archive() }
                }
            }
            Button(Strings.Cards.mergeIntoAnother, systemImage: "arrow.triangle.merge") {
                isMerging = true
            }
            if !card.hasTransactions {
                Button(Strings.Cards.deleteCard, systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog(Strings.Common.deleteNamed(card.name), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button(Strings.Cards.deleteCard, role: .destructive) { perform { try card.delete(in: context) } }
                }
            }
        } footer: {
            if card.hasTransactions {
                Text(Strings.Cards.archivedMergeFooter)
            } else {
                Text(Strings.Cards.archivedFooter)
            }
        }
    }

    private func save() {
        perform {
            switch mode {
            case .add:
                try Card.create(draftToSave, in: context)
            case .edit(let card):
                try card.update(with: draftToSave)
            }
        }
    }

    /// Runs a change and closes the sheet, or shows why the change was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            dismiss()
        } catch {
            Log.store.failed("Changing a card", error)
            errorMessage = error.localizedDescription
        }
    }
}
