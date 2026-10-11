import SwiftData
import SwiftUI

/// The Add Recurring transaction sheet, which also edits one. A new one starts as an Expense in the last-used wallet,
/// the way a new transaction does, and starts today.
struct RecurringTransactionEditor: View {
    let mode: EditorMode<RecurringTransaction>

    @Environment(\.modelContext) private var context

    var body: some View {
        RecurringForm(mode: mode, startingDraft: startingDraft)
    }

    private var startingDraft: RecurringDraft {
        switch mode {
        case .add:
            var draft = RecurringDraft(startDay: .today)
            draft.wallet = TransactionDefaults.suggest(on: .today, in: context).wallet
            return draft
        case .edit(let recurring):
            return RecurringDraft(editing: recurring)
        }
    }
}

/// The form behind ``RecurringTransactionEditor``, holding the draft from the moment the sheet opens.
private struct RecurringForm: View {
    let mode: EditorMode<RecurringTransaction>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: RecurringDraft
    @State private var entry: AmountEntry
    @State private var errorMessage: String?
    /// The start-date prompt, offered when the saved schedule has occurrences that have already come due.
    @State private var pastPrompt: PastPrompt?

    init(mode: EditorMode<RecurringTransaction>, startingDraft: RecurringDraft) {
        self.mode = mode
        _draft = State(initialValue: startingDraft)
        _entry = State(initialValue: AmountEntry(cents: startingDraft.amount.cents))
    }

    private var currencyCode: String { draft.wallet?.currencyCode ?? Money.defaultCurrencyCode }

    /// The draft with the amount the keypad comes to.
    private var draftToSave: RecurringDraft {
        var result = draft
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }

    /// The amount is tinted like the transactions it makes: red for an expense, green for income.
    private var amountTint: Color {
        draft.category.map { Money(cents: $0.sign).tint } ?? .primary
    }

    var body: some View {
        KeypadSheet(
            title: mode.isAdding ? Text("New Recurring Transaction") : Text("Edit Recurring Transaction"),
            entry: $entry,
            canSave: draftToSave.canSave,
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
            repeatSection
            endSection
        }
        .onChange(of: draft.category) { oldCategory, newCategory in
            // A new Recurring transaction is named after its category, until the user types a name of their own.
            if draft.name.isEmpty || draft.name == oldCategory?.name {
                draft.name = newCategory?.name ?? ""
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
            CardPicker(title: "Card", wallet: draft.wallet, selection: $draft.card)
            fields.noteField($draft.note)
            DayStepper(title: "Starts", day: $draft.startDay)
        } footer: {
            Text("Each time it falls due, a transaction is made with this name, amount, wallet, category and Card.")
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
            let startChanged = mode.editing.map { $0.schedule.start != draftToSave.startDay } ?? true
            let saved: RecurringTransaction
            switch mode {
            case .add:
                saved = try RecurringTransaction.create(draftToSave, in: context)
            case .edit(let recurring):
                try recurring.update(with: draftToSave)
                saved = recurring
            }
            let unentered = saved.unenteredOccurrences(through: .today)
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
