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
        MadeOnce(make: makeStartingDraft) { draft in
            TransactionForm(mode: mode, startingDraft: draft)
        }
    }

    private func makeStartingDraft() -> TransactionDraft {
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

    @Environment(\.modelContext) private var context

    @AppStorage(AppSettings.sounds) private var soundsOn
    @AppStorage(AppSettings.haptics) private var hapticsOn
    @AppStorage(AppSettings.chime) private var chime

    @State private var draft: TransactionDraft
    @State private var isShowingDetails: Bool

    init(mode: TransactionEditor.Mode, startingDraft: TransactionDraft) {
        self.mode = mode
        _draft = State(initialValue: startingDraft)
        _isShowingDetails = State(initialValue: startingDraft.hasDetails)
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    var body: some View {
        KeypadSheet(
            title: isEditing ? Text(Strings.Transactions.editTransaction) : Text(Strings.Transactions.addTransaction),
            entry: $draft.entry,
            canSave: draft.canSave,
            size: .tallKeypadForm,
            saving: "Saving a transaction",
            failureTitle: Strings.Transactions.couldntSave,
            save: save
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
            detailsSection
        }
        .onChange(of: draft.offersReminder) {
            // A Loan or Debt opens the details, where its reminder is.
            if draft.offersReminder {
                isShowingDetails = true
            }
        }
    }

    private func mainSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            WalletPicker(title: Strings.Common.wallet, selection: $draft.wallet)
                .disabled(draft.isLockedByPayments)
            fields.amountRow(Strings.Common.amount, currencyCode: draft.currencyCode, tint: draft.direction.tint)
            CategoryPicker(title: Strings.Common.category, type: draft.type, selection: $draft.category)
                .disabled(draft.isLockedByPayments)
                .accessibilityIdentifier("TransactionEditor.category")
            if draft.offersCard {
                CardPicker(title: Strings.Common.card, wallet: draft.wallet, category: draft.category, selection: $draft.card)
                    .accessibilityIdentifier("TransactionEditor.card")
            }
            fields.noteField($draft.note)
                .accessibilityIdentifier("TransactionEditor.note")
            DayStepper(title: Strings.Common.date, day: $draft.day)
        } footer: {
            if let problem = draft.shownProblem {
                Text(problem.localizedDescription)
            } else if draft.paymentLock?.forgivenOwed != nil {
                Text(Strings.Transactions.forgivenLockFooter)
            } else if let paymentLock = draft.paymentLock {
                Text(Strings.Transactions.paymentsLockFooter(paymentLock.paid.formatted()))
            }
        }
    }

    /// Add more details: With and its + Owes me first, then a section for each Person who owes, then the rest, so one
    /// Person's Owes me is set apart from the next one's and from the other details.
    @ViewBuilder
    private var detailsSection: some View {
        Section {
            DisclosureGroup(Strings.Transactions.addMoreDetails, isExpanded: $isShowingDetails) {
                WithField(people: $draft.people, picksOne: draft.requiresWith)
                OwesMeAddButtons(draft: $draft)
            }
        } footer: {
            if draft.isMissingWith {
                Text(TransactionRuleError.missingWith.localizedDescription)
            }
        }
        if isShowingDetails {
            OwesMeSections(draft: $draft)
            otherDetailsSection
        }
    }

    private var otherDetailsSection: some View {
        Section {
            Toggle(Strings.Common.excludeFromReport, isOn: $draft.isExcludedFromReport)
            if draft.offersReminder {
                ReminderField(day: $draft.reminderDay)
            }
            // Location and Event are planned, so they show greyed out until a transaction can set them here. A part
            // of a Split already sets its own Event.
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
        } footer: {
            Text(Strings.Common.excludedFromReportFooter)
        }
    }

    private func save() throws {
        try Signpost.interval("Save transaction") {
            switch mode {
            case .add, .duplicate:
                try Transaction.create(draft, in: context)
            case .payment(let recurring):
                let transaction = try Transaction.create(draft, in: context)
                try recurring.attach(transaction)
            case .edit(let transaction):
                try transaction.update(with: draft)
            }
        }
        playSuccessCue()
    }

    /// Plays the Success cue for a new Expense or Income that just saved, with the chime picked in Settings and as its
    /// switches allow. It never holds up the sheet closing, and a cue that can't play is skipped without a word.
    private func playSuccessCue() {
        guard let ending = mode.successCueEnding(saving: draft.type) else { return }
        SuccessCuePlayer.shared.play(
            chime,
            ending: ending,
            sound: SoundsAndHaptics.plays(on: .current, isOn: soundsOn),
            haptic: SoundsAndHaptics.plays(on: .current, isOn: hapticsOn)
        )
    }
}

private extension TransactionDraft {
    /// Whether any of the "more details" are filled in, so they open already showing.
    var hasDetails: Bool {
        offersReminder || !people.isEmpty || isExcludedFromReport || !eventName.isEmpty
    }
}

#Preview {
    TransactionEditor(mode: .add)
        .modelContainer(try! StoreOpening.open(inMemory: true))
}
