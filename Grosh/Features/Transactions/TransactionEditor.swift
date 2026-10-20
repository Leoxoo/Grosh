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

    var body: some View {
        TransactionForm(mode: mode, startingDraft: startingDraft)
    }

    private var startingDraft: TransactionDraft {
        switch mode {
        case .add: TransactionDefaults.suggest(on: .today, in: context)
        case .duplicate(let transaction): TransactionDraft(duplicating: transaction, on: .today)
        case .payment(let recurring): TransactionDraft(paymentFor: recurring, on: .today)
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
                .disabled(draft.isLockedByPayments)
            }

            mainSection(fields)
            detailsSection
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
                .disabled(draft.isLockedByPayments)
            fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: draft.sign).tint)
            CategoryPicker(title: "Category", type: draft.type, selection: $draft.category)
                .disabled(draft.isLockedByPayments)
            if draft.offersCard {
                CardPicker(title: "Card", wallet: draft.wallet, selection: $draft.card)
            }
            fields.noteField($draft.note)
            DayStepper(title: "Date", day: $draft.day)
        } footer: {
            if draft.wallet == nil {
                Text("Add a wallet first, in Account → Wallets.")
            } else if draft.paymentLock?.forgivenOwed != nil {
                Text("It's forgiven, so it keeps its amount, wallet and category until it's un-forgiven.")
            } else if let paymentLock = draft.paymentLock {
                Text("Its payments keep the wallet and category. The amount can't be less than the \(paymentLock.paid.formatted()) already paid back.")
            } else if draftToSave.requiresCard && draft.card == nil {
                Text("Choose the Card this expense was paid with. Expenses need a Card when their wallet has one.")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            DisclosureGroup("Add more details", isExpanded: $isShowingDetails) {
                WithField(people: $draft.people, picksOne: draft.requiresWith)
                Toggle("Exclude from report", isOn: $draft.isExcludedFromReport)
                if draft.offersReminder {
                    ReminderField(day: $draft.reminderDay)
                }
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
            if draft.isMissingWith {
                Text("A Loan or Debt needs a With: who you lent to or borrowed from.")
            } else if isShowingDetails {
                Text("A transaction excluded from report still counts in balances, just not in income and spending.")
            }
        }
    }

    private func save() {
        do {
            switch mode {
            case .add, .duplicate:
                try Transaction.create(draftToSave, in: context)
            case .payment(let recurring):
                let transaction = try Transaction.create(draftToSave, in: context)
                try recurring.attach(transaction, in: context)
            case .edit(let transaction):
                try transaction.update(with: draftToSave)
            }
            playSuccessCue()
            dismiss()
        } catch {
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

private extension TransactionDraft {
    /// Whether any of the "more details" are filled in, so they open already showing.
    var hasDetails: Bool {
        type == .debtLoan || !people.isEmpty || isExcludedFromReport || !eventName.isEmpty
    }
}

#Preview {
    TransactionEditor(mode: .add)
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
