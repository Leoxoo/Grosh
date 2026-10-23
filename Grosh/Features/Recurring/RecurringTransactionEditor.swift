import SwiftData
import SwiftUI

/// The Add Recurring transaction sheet. It also edits one, and opens pre-filled for Duplicate. A new one starts as an
/// Expense in the last-used wallet, the way a new transaction does, and starts today.
struct RecurringTransactionEditor: View {
    enum Mode: Identifiable {
        case add
        /// A new Recurring transaction pre-filled from this one, starting today.
        case duplicate(RecurringTransaction)
        case edit(RecurringTransaction)

        var id: AnyHashable {
            switch self {
            case .add: "add"
            case .duplicate(let recurring): ["duplicate", recurring.persistentModelID] as [AnyHashable]
            case .edit(let recurring): ["edit", recurring.persistentModelID] as [AnyHashable]
            }
        }
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    var body: some View {
        RecurringForm(mode: mode, startingDraft: startingDraft)
    }

    private var startingDraft: RecurringDraft {
        switch mode {
        case .add:
            var draft = RecurringDraft(startDay: today)
            draft.wallet = TransactionDefaults.suggest(on: today, in: context).wallet
            return draft
        case .duplicate(let recurring):
            return RecurringDraft(duplicating: recurring, on: today)
        case .edit(let recurring):
            return RecurringDraft(editing: recurring)
        }
    }
}

/// The form behind ``RecurringTransactionEditor``, holding the draft from the moment the sheet opens.
private struct RecurringForm: View {
    let mode: RecurringTransactionEditor.Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today

    @State private var draft: RecurringDraft
    @State private var entry: AmountEntry
    /// A Purchase's total price as the keypad shows it. Zero is no total.
    @State private var totalEntry: AmountEntry
    @State private var errorMessage: String?
    /// The start-date prompt, offered when the saved schedule has occurrences that have already come due.
    @State private var pastPrompt: PastPrompt?

    init(mode: RecurringTransactionEditor.Mode, startingDraft: RecurringDraft) {
        self.mode = mode
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: AmountEntry(cents: startingDraft.amount.cents))
        _totalEntry = State(initialValue: AmountEntry(cents: startingDraft.total?.cents ?? 0))
    }

    /// Whether the sheet saves a new Recurring transaction, which Add and Duplicate both do.
    private var isNew: Bool {
        if case .edit = mode { false } else { true }
    }

    /// The Recurring transaction being edited, or `nil` when it is new.
    private var editing: RecurringTransaction? {
        if case .edit(let recurring) = mode { recurring } else { nil }
    }

    private var currencyCode: String { draft.wallet?.currencyCode ?? Money.defaultCurrencyCode }

    /// The estimate a varying Bill starts at: the average of its category's history, or `nil` when there is none.
    private var estimateCents: Int? {
        guard draft.estimatesAmount, let category = draft.category else { return nil }
        return AmountEstimate.cents(for: category, currencyCode: currencyCode)
    }

    /// The draft with the amounts the keypad comes to. A total of zero is no total.
    private var draftToSave: RecurringDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        result.estimateCents = estimateCents
        if let cents = totalEntry.cents, cents > 0 {
            result.total = Money(cents: cents, currencyCode: currencyCode)
        } else {
            result.total = nil
        }
        return result
    }

    /// The amount is tinted like the transactions it makes: red for an expense, green for income.
    private var amountTint: Color {
        draft.category.map { Money(cents: $0.sign).tint } ?? .primary
    }

    var body: some View {
        KeypadSheet(
            title: isNew ? Text("New Recurring Transaction") : Text("Edit Recurring Transaction"),
            entry: $entry,
            secondEntry: $totalEntry,
            canSave: draftToSave.canSave && totalEntry.cents != nil,
            save: save,
            macHeight: (640, 720)
        ) { fields in
            Section {
                Picker("Type", selection: $draft.type) {
                    Text(CategoryType.expense.title).tag(CategoryType.expense)
                    Text(CategoryType.income.title).tag(CategoryType.income)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            detailsSection(fields)
            if draft.kind == .bill {
                estimateSection
            }
            if draft.kind == .purchase {
                purchaseSection(fields)
            }
            repeatSection
            endSection
        }
        .onChange(of: draft.category) { oldCategory, newCategory in
            // A new Recurring transaction is named after its category, until the user types a name of their own.
            if draft.name.isEmpty || draft.name == oldCategory?.name {
                draft.name = newCategory?.name ?? ""
            }
            // A new Recurring transaction starts as its category's default Kind, which the user can change.
            if isNew, let newCategory {
                draft.kind = newCategory.defaultKind
            }
        }
        .errorAlert("Couldn't Save Recurring Transaction", message: $errorMessage)
        .sheet(item: $pastPrompt, onDismiss: { dismiss() }) { prompt in
            PastOccurrencesView(recurring: prompt.recurring, days: prompt.days)
        }
    }

    private func detailsSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            TextField("Name", text: $draft.name)
            fields.amountRow("Amount", currencyCode: currencyCode, tint: amountTint)
            WalletPicker(title: "Wallet", selection: $draft.wallet)
            CategoryPicker(title: "Category", type: draft.type, selection: $draft.category)
            Picker("Kind", selection: $draft.kind) {
                ForEach(RecurringKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            if draft.kind == .subscription {
                PhotoField(shape: .appIcon, data: $draft.iconData)
            }
            CardPicker(title: "Card", wallet: draft.wallet, selection: $draft.card)
            fields.noteField($draft.note)
            DayStepper(title: "Starts", day: $draft.startDay)
        } footer: {
            Text("Each time it falls due, a transaction is made with this name, amount, wallet, category and Card.")
        }
    }

    /// A Bill's amount can vary: each transaction then starts as an estimate, and the user is reminded to enter the
    /// real one. The amount above can be left empty when there is an estimate to start from.
    private var estimateSection: some View {
        Section {
            Toggle("Amount varies", isOn: $draft.amountVaries)
            if draft.amountVaries {
                LabeledContent("Estimate", value: estimateText)
                Stepper(value: $draft.remindAfterDays, in: 1...30) {
                    Text(remindAfterText)
                }
            }
        } footer: {
            Text("Each transaction starts as an estimate, the average of recent transactions in its category, until you enter the real amount. The amount above is used only when the category has no history yet.")
        }
    }

    private var estimateText: String {
        guard let cents = estimateCents else { return String(localized: "None yet") }
        return Money(cents: cents, currencyCode: currencyCode).formatted()
    }

    private var remindAfterText: String {
        draft.remindAfterDays == 1
            ? String(localized: "Remind me 1 day later")
            : String(localized: "Remind me \(draft.remindAfterDays) days later")
    }

    /// A Purchase's optional total price. Payments attached to it count as paid toward it; the schedule doesn't change.
    private func purchaseSection(_ fields: KeypadSheetFields) -> some View {
        Section {
            fields.secondAmountRow("Total price", currencyCode: currencyCode)
        } footer: {
            Text("Payments attached to it count as paid toward this total. Leave it at zero when there isn't one.")
        }
    }

    private var repeatSection: some View {
        Section {
            Picker("Repeat", selection: $draft.preset) {
                ForEach(RepeatPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            if draft.preset == .custom {
                Stepper(value: $draft.customRule.every, in: 1...365) {
                    Text("Every \(draft.customRule.every)")
                }
                Picker("Unit", selection: $draft.customRule.unit) {
                    ForEach(RepeatUnit.allCases, id: \.self) { unit in
                        Text(unit.pluralTitle).tag(unit)
                    }
                }
            }
            if draft.rule.unit == .month {
                // Each choice is written out in full, as the detail screen reads it.
                Picker("On", selection: $draft.monthlyDay) {
                    ForEach(MonthlyDay.offered(startingOn: draft.startDay), id: \.self) { option in
                        Text(draft.rule.phrase + " " + option.phrase(startingOn: draft.startDay)).tag(option)
                    }
                }
            }
        } footer: {
            Text(draft.schedule.summary)
        }
    }

    private var endSection: some View {
        Section {
            Picker("Ends", selection: $draft.endKind) {
                ForEach(RepeatEndKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            if draft.endKind == .until {
                DayPicker(title: "Last day", day: $draft.untilDay, earliest: draft.startDay)
            }
            if draft.endKind == .afterCount {
                Stepper(value: $draft.occurrenceCount, in: 1...999) {
                    Text(occurrenceCountText)
                }
            }
        }
    }

    private var occurrenceCountText: String {
        draft.occurrenceCount == 1
            ? String(localized: "Once")
            : String(localized: "\(draft.occurrenceCount) times")
    }

    private func save() {
        do {
            // A new schedule, or one whose start day has been moved, offers the occurrences that have already come due.
            let startChanged = editing.map { $0.schedule.start != draftToSave.startDay } ?? true
            let saved: RecurringTransaction
            switch mode {
            case .add, .duplicate:
                saved = try RecurringTransaction.create(draftToSave, today: today, in: context)
            case .edit(let recurring):
                try recurring.update(with: draftToSave, today: today)
                saved = recurring
            }
            let unentered = saved.unenteredOccurrences(through: today)
            if startChanged && !unentered.isEmpty {
                pastPrompt = PastPrompt(recurring: saved, days: unentered)
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The start-date prompt for a Recurring transaction the editor has just saved, and the days it offers.
private struct PastPrompt: Identifiable {
    let id = UUID()
    let recurring: RecurringTransaction
    let days: [CalendarDay]
}

#Preview {
    RecurringTransactionEditor(mode: .add)
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
