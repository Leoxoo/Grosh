import SwiftData
import SwiftUI

/// The Add Transaction sheet. It also edits a transaction, and opens pre-filled for Duplicate or for a payment toward a
/// Purchase.
/// It makes no default-value decisions of its own: a new transaction starts from suggest-defaults
/// (``TransactionDefaults``); Duplicate and Edit start from the transaction.
struct TransactionEditor: View {
    enum Mode: Identifiable {
        case add
        /// A new transaction pre-filled from this one, dated today.
        case duplicate(Transaction)
        /// A new payment toward a Purchase, pre-filled from it and dated today. Saving attaches it to the Purchase.
        case payment(RecurringTransaction)
        case edit(Transaction)

        var id: AnyHashable {
            switch self {
            case .add: "add"
            case .duplicate(let transaction): ["duplicate", transaction.persistentModelID] as [AnyHashable]
            case .payment(let recurring): ["payment", recurring.persistentModelID] as [AnyHashable]
            case .edit(let transaction): ["edit", transaction.persistentModelID] as [AnyHashable]
            }
        }

        /// How the Success cue ends once a transaction of `type` saves in this mode, or `nil` when it plays none: only
        /// a new Expense or Income plays it, whether added, duplicated or paid toward a Purchase. An edit never does.
        func successCueEnding(saving type: CategoryType) -> SuccessCue.Ending? {
            switch self {
            case .add, .duplicate, .payment: SuccessCue.Ending(newTransactionOf: type)
            case .edit: nil
            }
        }
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    var body: some View {
        TransactionForm(mode: mode, startingDraft: startingDraft)
    }

    private var startingDraft: TransactionDraft {
        switch mode {
        case .add: TransactionDefaults.suggest(on: today, in: context)
        case .duplicate(let transaction): TransactionDraft(duplicating: transaction, on: today)
        case .payment(let recurring): TransactionDraft(paymentFor: recurring, on: today)
        case .edit(let transaction): TransactionDraft(editing: transaction)
        }
    }
}

/// The form behind ``TransactionEditor``, holding the draft from the moment the sheet opens.
private struct TransactionForm: View {
    let mode: TransactionEditor.Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(SoundsAndHaptics.soundsKey) private var soundsOn = SoundsAndHaptics.defaultIsOn
    @AppStorage(SoundsAndHaptics.hapticsKey) private var hapticsOn = SoundsAndHaptics.defaultIsOn
    @AppStorage(SoundsAndHaptics.chimeKey) private var chime = SuccessCue.Chime.default

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
            title: isEditing ? Text(Strings.Transactions.editTransaction) : Text(Strings.Transactions.addTransaction),
            entry: $entry,
            canSave: draftToSave.canSave,
            save: save,
            macHeight: (640, 720)
        ) { fields in
            Section {
                Picker(Strings.Common.type, selection: $draft.type) {
                    ForEach(draft.types, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(draft.isLockedByPayments)
            }

            mainSection(fields)
            detailsSection(fields)
        }
        .onChange(of: draft.type) {
            if draft.type == .debtLoan {
                isShowingDetails = true
            }
        }
        .errorAlert(Strings.Transactions.couldntSave, message: $errorMessage)
    }

    private func mainSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            WalletPicker(title: Strings.Common.wallet, selection: $draft.wallet)
                .disabled(draft.isLockedByPayments)
            fields.amountRow(Strings.Common.amount, currencyCode: currencyCode, tint: Money(cents: draft.sign).tint)
            CategoryPicker(title: Strings.Common.category, type: draft.type, selection: $draft.category)
                .disabled(draft.isLockedByPayments)
                .accessibilityIdentifier("TransactionEditor.category")
            if draft.offersCard {
                CardPicker(title: Strings.Common.card, wallet: draft.wallet, selection: $draft.card)
                    .accessibilityIdentifier("TransactionEditor.card")
            }
            fields.noteField($draft.note)
                .accessibilityIdentifier("TransactionEditor.note")
            DayStepper(title: Strings.Common.date, day: $draft.day)
        } footer: {
            if draft.wallet == nil {
                Text(Strings.Common.addWalletFirst)
            } else if draft.paymentLock?.forgivenOwed != nil {
                Text(Strings.Transactions.forgivenLockFooter)
            } else if let paymentLock = draft.paymentLock {
                Text(Strings.Transactions.paymentsLockFooter(paymentLock.paid.formatted()))
            } else if draftToSave.requiresCard && draft.card == nil {
                Text(Strings.Transactions.cardRequiredFooter)
            }
        }
    }

    private func detailsSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            DisclosureGroup(Strings.Transactions.addMoreDetails, isExpanded: $isShowingDetails) {
                TextField(Strings.Common.with, text: $draft.withName)
                    .focused(fields.focus, equals: .withName)
                if fields.focus.wrappedValue == .withName {
                    WithNameSuggestions(typed: draft.withName) { name in
                        draft.withName = name
                        fields.focus.wrappedValue = nil
                    }
                }
                Toggle(Strings.Common.excludeFromReport, isOn: $draft.isExcludedFromReport)
                if draft.offersReminder {
                    ReminderField(day: $draft.reminderDay)
                }
                LabeledContent {
                    Text(Strings.Transactions.comingSoon)
                } label: {
                    Label(Strings.Transactions.location, systemImage: "mappin.and.ellipse")
                }
                .foregroundStyle(.tertiary)
                LabeledContent {
                    Text(draft.eventName.isEmpty ? String(localized: Strings.Common.none) : draft.eventName)
                } label: {
                    Label(Strings.Common.event, systemImage: "calendar")
                }
                .foregroundStyle(.tertiary)
            }
        } footer: {
            if draft.isMissingWith {
                Text(Strings.Transactions.withRequiredFooter)
            } else if isShowingDetails {
                Text(Strings.Transactions.excludedEditorFooter)
            }
        }
    }

    private func save() {
        do {
            try Signpost.interval("Save transaction") {
                switch mode {
                case .add, .duplicate:
                    try Transaction.create(draftToSave, in: context)
                case .payment(let recurring):
                    let transaction = try Transaction.create(draftToSave, in: context)
                    try recurring.attach(transaction, in: context)
                case .edit(let transaction):
                    try transaction.update(with: draftToSave)
                }
            }
            playSuccessCue()
            dismiss()
        } catch {
            Log.store.failed("Saving a transaction", error)
            errorMessage = error.localizedDescription
        }
    }

    /// Plays the Success cue for a new Expense or Income that just saved, with the chime picked in Settings and as its
    /// switches allow. It never holds up the sheet closing, and a cue that can't play is skipped without a word.
    private func playSuccessCue() {
        guard let ending = mode.successCueEnding(saving: draftToSave.type) else { return }
        SuccessCuePlayer.shared.play(
            chime,
            ending: ending,
            sound: SoundsAndHaptics.playsSounds(on: .current, soundsOn: soundsOn),
            haptic: SoundsAndHaptics.playsHaptics(on: .current, hapticsOn: hapticsOn)
        )
    }
}

/// Names used before that match what's typed in the With field, to pick with one tap.
struct WithNameSuggestions: View {
    let typed: String
    let onPick: (String) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let names = Log.store.attempt("Reading the With names") {
            try Transaction.withNames(matching: typed, limit: 3, in: context)
        } ?? []
        ForEach(names, id: \.self) { name in
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
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
