import SwiftData
import SwiftUI

/// Adds a Card or edits one. Editing also archives, merges or deletes it.
struct CardEditor: View {
    let mode: EditorMode<Card>

    var body: some View {
        MadeOnce {
            (
                draft: mode.editing.map { CardDraft($0) } ?? CardDraft.new,
                hasTransactions: mode.editing.map { card in
                    Log.store.attempt("Counting a Card's transactions") { try card.hasTransactions() } ?? true
                } ?? false
            )
        } content: { start in
            CardForm(mode: mode, startingDraft: start.draft, hasTransactions: start.hasTransactions)
        }
    }
}

/// The form behind ``CardEditor``, holding the draft from the moment the sheet opens.
private struct CardForm: View {
    let mode: EditorMode<Card>
    /// Whether the Card being edited paid for anything, counted in the store once when the sheet opens. When the
    /// store can't be read it counts as having paid, so nothing is offered on a guess.
    let hasTransactions: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(Wallet.unarchived) private var wallets: [Wallet]

    @State private var draft: CardDraft
    @State private var isMerging = false
    @State private var isConfirmingDelete = false
    private let saver = SheetSaver(Strings.Cards.couldntSave)

    init(mode: EditorMode<Card>, startingDraft: CardDraft, hasTransactions: Bool) {
        self.mode = mode
        self.hasTransactions = hasTransactions
        _draft = State(initialValue: startingDraft)
    }

    /// The Card being edited, until it is merged away or deleted (the sheet may draw once more while closing).
    private var editedCard: Card? {
        guard let card = mode.editing, !card.isGone else { return nil }
        return card
    }

    /// A Card that paid for transactions keeps its paying wallet.
    private var isPayingWalletFixed: Bool { editedCard != nil && hasTransactions }

    var body: some View {
        let check = draft.check
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
                    } else if let problem = check.shownProblem {
                        Text(problem.localizedDescription)
                            .foregroundStyle(.invalid)
                    } else {
                        Text(Strings.Cards.onlyALabelFooter)
                    }
                }

                if draft.offersStatementDate {
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
                        .disabled(!check.passes)
                }
            }
            .onAppear {
                draft.startPaying(from: wallets)
            }
            .sheet(isPresented: $isMerging) {
                if let card = editedCard {
                    CardMergeView(source: card) { dismiss() }
                }
            }
            .failureAlert(saver)
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
            set: { draft.setLastFourDigits(typed: $0) }
        )
    }

    private var statementSection: some View {
        Section {
            Toggle(Strings.Cards.statementDate, isOn: $draft.hasStatementDate)
            if draft.hasStatementDate {
                Picker(Strings.Cards.closesOnThe, selection: $draft.statementDayChoice) {
                    ForEach(1...31, id: \.self) { day in
                        Text(CalendarDay.ordinal(day)).tag(day)
                    }
                }
            }
        } footer: {
            if draft.hasStatementDate {
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
                    saver.save("Changing a card") { try card.unarchive() }
                }
            } else {
                Button(Strings.Cards.archiveCard, systemImage: "archivebox") {
                    saver.save("Changing a card") { try card.archive() }
                }
            }
            Button(Strings.Cards.mergeIntoAnother, systemImage: "arrow.triangle.merge") {
                isMerging = true
            }
            if !hasTransactions {
                Button(Strings.Cards.deleteCard, systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog(Strings.Common.deleteNamed(card.name), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button(Strings.Cards.deleteCard, role: .destructive) { saver.save("Changing a card") { try card.delete() } }
                }
            }
        } footer: {
            if hasTransactions {
                Text(Strings.Cards.archivedMergeFooter)
            } else {
                Text(Strings.Cards.archivedFooter)
            }
        }
    }

    private func save() {
        saver.save("Changing a card") {
            switch mode {
            case .add:
                try Card.create(draft, in: context)
            case .edit(let card):
                try card.update(with: draft)
            }
        }
    }
}
