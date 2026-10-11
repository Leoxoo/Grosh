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
            if draft.kind == .bill {
                estimateSection
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
            if mode.isAdding, let newCategory {
                draft.kind = newCategory.defaultKind
            }
        }
        .errorAlert("Couldn't Save Recurring Transaction", message: $errorMessage)
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
            CardPicker(title: "Card", wallet: draft.wallet, selection: $draft.card)
            fields.noteField($draft.note)
            DayStepper(title: "Starts", day: $draft.startDay)
        } footer: {
            Text("Each time it falls due, a transaction is made with this name, amount, wallet, category and Card.")
        }
    }

    /// A Bill's amount can vary: each transaction then starts as an estimate, and the user is reminded to enter the
    /// real one.
    private var estimateSection: some View {
        Section {
            Toggle("Amount varies", isOn: $draft.amountVaries)
            if draft.amountVaries {
                Stepper(value: $draft.remindAfterDays, in: 1...30) {
                    Text(remindAfterText)
                }
            }
        } footer: {
            Text("Each transaction starts as an estimate, the average of recent transactions in its category, until you enter the real amount.")
        }
    }

    private var remindAfterText: String {
        draft.remindAfterDays == 1
            ? String(localized: "Remind me 1 day later")
            : String(localized: "Remind me \(draft.remindAfterDays) days later")
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
            switch mode {
            case .add:
                try RecurringTransaction.create(draftToSave, in: context)
            case .edit(let recurring):
                try recurring.update(with: draftToSave)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RecurringTransactionEditor(mode: .add)
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
