import SwiftData
import SwiftUI

/// The Add Transaction sheet. It also edits a transaction, and opens pre-filled for Duplicate.
/// It makes no default-value decisions of its own: a new transaction starts from suggest-defaults
/// (``TransactionDefaults``); Duplicate and Edit start from the transaction.
struct TransactionEditor: View {
    enum Mode: Identifiable {
        case add
        /// A new transaction pre-filled from this one, dated today.
        case duplicate(Transaction)
        case edit(Transaction)

        var id: AnyHashable {
            switch self {
            case .add: "add"
            case .duplicate(let transaction): ["duplicate", transaction.persistentModelID] as [AnyHashable]
            case .edit(let transaction): ["edit", transaction.persistentModelID] as [AnyHashable]
            }
        }
    }

    let mode: Mode

    @Environment(\.modelContext) private var context

    var body: some View {
        TransactionForm(mode: mode, startingDraft: startingDraft)
    }

    private var startingDraft: TransactionDraft {
        switch mode {
        case .add: TransactionDefaults.suggest(on: .today, in: context)
        case .duplicate(let transaction): TransactionDraft(duplicating: transaction, on: .today)
        case .edit(let transaction): TransactionDraft(editing: transaction)
        }
    }
}

/// The form behind ``TransactionEditor``, holding the draft from the moment the sheet opens.
private struct TransactionForm: View {
    let mode: TransactionEditor.Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: TransactionDraft
    @State private var entry: AmountEntry
    @State private var isShowingDetails: Bool
    @State private var errorMessage: String?

    init(mode: TransactionEditor.Mode, startingDraft: TransactionDraft) {
        self.mode = mode
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: AmountEntry(cents: startingDraft.amount.cents))
        _isShowingDetails = State(initialValue: startingDraft.hasDetails)
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var currencyCode: String { draft.wallet?.currencyCode ?? Money.defaultCurrencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: TransactionDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    var body: some View {
        KeypadSheet(
            title: isEditing ? Text("Edit Transaction") : Text("Add Transaction"),
            entry: $entry,
            canSave: draftToSave.canSave,
            save: save,
            macHeight: (640, 720)
        ) { fields in
            Section {
                Picker("Type", selection: $draft.type) {
                    ForEach(draft.types, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            mainSection(fields)
            detailsSection(fields)
        }
        .onChange(of: draft.type) {
            if draft.type == .debtLoan {
                isShowingDetails = true
            }
        }
        .errorAlert("Couldn't Save Transaction", message: $errorMessage)
    }

    private func mainSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            WalletPicker(title: "Wallet", selection: $draft.wallet)
            fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: draft.sign).tint)
            CategoryPicker(title: "Category", type: draft.type, selection: $draft.category)
            if draft.offersCard {
                CardPicker(title: "Card", wallet: draft.wallet, selection: $draft.card)
            }
            fields.noteField($draft.note)
            DayStepper(title: "Date", day: $draft.day)
        } footer: {
            if draft.wallet == nil {
                Text("Add a wallet first, in Account → Wallets.")
            } else if draftToSave.requiresCard && draft.card == nil {
                Text("Choose the Card this expense was paid with. Expenses need a Card when their wallet has one.")
            }
        }
    }

    private func detailsSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            DisclosureGroup("Add more details", isExpanded: $isShowingDetails) {
                TextField("With", text: $draft.withName)
                    .focused(fields.focus, equals: .withName)
                if fields.focus.wrappedValue == .withName {
                    WithNameSuggestions(typed: draft.withName) { name in
                        draft.withName = name
                        fields.focus.wrappedValue = nil
                    }
                }
                Toggle("Exclude from report", isOn: $draft.isExcludedFromReport)
                LabeledContent {
                    Text("Coming soon")
                } label: {
                    Label("Location", systemImage: "mappin.and.ellipse")
                }
                .foregroundStyle(.tertiary)
                LabeledContent {
                    Text(draft.eventName.isEmpty ? String(localized: "None") : draft.eventName)
                } label: {
                    Label("Event", systemImage: "calendar")
                }
                .foregroundStyle(.tertiary)
            }
        } footer: {
            if isShowingDetails {
                Text("A transaction excluded from report still counts in balances, just not in income and spending.")
            }
        }
    }

    private func save() {
        do {
            switch mode {
            case .add, .duplicate:
                try Transaction.create(draftToSave, in: context)
            case .edit(let transaction):
                try transaction.update(with: draftToSave)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Names used before that match what's typed in the With field, to pick with one tap.
private struct WithNameSuggestions: View {
    let typed: String
    let onPick: (String) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        ForEach((try? Transaction.withNames(matching: typed, limit: 3, in: context)) ?? [], id: \.self) { name in
            Button {
                onPick(name)
            } label: {
                Label(name, systemImage: "person.crop.circle")
            }
        }
    }
}

private extension TransactionDraft {
    /// Whether any of the "more details" are filled in, so they open already showing.
    var hasDetails: Bool {
        type == .debtLoan || !withName.isEmpty || isExcludedFromReport || !eventName.isEmpty
    }
}

#Preview {
    TransactionEditor(mode: .add)
        .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
