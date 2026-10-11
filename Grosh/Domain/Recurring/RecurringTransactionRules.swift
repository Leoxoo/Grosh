import Foundation
import SwiftData

/// Why a Recurring transaction can't be saved yet.
nonisolated enum RecurringRuleError: Error, Equatable {
    case missingName
    case missingWallet
    /// The amount must be above zero; the category sets the sign.
    case missingAmount
    case missingCategory
    /// A Card is only offered on its paying wallet's transactions, so it must be paid from the wallet chosen.
    case cardNotInWallet
    /// An end "until a date" must fall on or after the start date.
    case untilBeforeStart
    /// An end "after N times" needs at least one occurrence.
    case noOccurrences
}

extension RecurringRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "Give the recurring transaction a name.")
        case .missingWallet: String(localized: "Choose a wallet.")
        case .missingAmount: String(localized: "Enter an amount above zero.")
        case .missingCategory: String(localized: "Choose a category.")
        case .cardNotInWallet: String(localized: "Choose a Card paid from this wallet.")
        case .untilBeforeStart: String(localized: "The last day can't be before the start date.")
        case .noOccurrences: String(localized: "Repeat at least once.")
        }
    }
}

/// The editable fields of a Recurring transaction, as its form holds them before the rules check and save them.
struct RecurringDraft {
    var name = ""
    /// Entered positive; the category sets the sign.
    var amount = Money(cents: 0)
    /// Expense or Income. Switching it drops a category of the other type.
    var type: CategoryType = .expense {
        didSet {
            if category?.type != type {
                category = nil
            }
        }
    }
    /// Changing it drops the Card, which is only offered on its paying wallet's transactions.
    var wallet: Wallet? {
        didSet {
            if wallet != oldValue {
                card = nil
            }
        }
    }
    var category: Category?
    var card: Card?
    /// The sort of Recurring transaction it is. A new one starts with its category's default Kind.
    var kind: RecurringKind = .regular
    var note = ""
    /// The first occurrence. It may be in the past.
    var startDay: CalendarDay
    /// The repeat the form names. ``RepeatPreset/custom`` takes ``customRule``.
    var preset: RepeatPreset = .monthly {
        didSet {
            if preset == .custom {
                customRule = oldValue.rule ?? customRule
            }
        }
    }
    var customRule = RepeatRule(unit: .month, every: 1)
    var endKind: RepeatEndKind = .forever
    /// The last day, for an end "until a date".
    var untilDay: CalendarDay
    /// The number of occurrences, for an end "after N times".
    var occurrenceCount = 12

    init(startDay: CalendarDay) {
        self.startDay = startDay
        untilDay = startDay.adding(days: 365)
    }

    /// The Recurring transaction's current fields, ready to edit.
    init(editing recurring: RecurringTransaction) {
        let schedule = recurring.schedule
        self.init(startDay: schedule.start)
        name = recurring.name
        amount = Money(
            cents: recurring.amountCents,
            currencyCode: recurring.wallet?.currencyCode ?? Money.defaultCurrencyCode
        )
        type = recurring.category?.type ?? .expense
        wallet = recurring.wallet
        category = recurring.category
        card = recurring.card
        kind = recurring.kind
        note = recurring.note
        preset = RepeatPreset(rule: schedule.rule)
        customRule = schedule.rule
        endKind = schedule.end.kind
        switch schedule.end {
        case .forever: break
        case .until(let last): untilDay = last
        case .afterCount(let count): occurrenceCount = count
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The repeat the form has picked.
    var rule: RepeatRule { preset.rule ?? customRule }

    /// When the Recurring transaction ends, as the form has it.
    var end: RepeatEnd {
        switch endKind {
        case .forever: .forever
        case .until: .until(untilDay)
        case .afterCount: .afterCount(occurrenceCount)
        }
    }

    /// When the Recurring transaction falls due, as the form has it.
    var schedule: RepeatSchedule {
        RepeatSchedule(start: startDay, rule: rule, end: end)
    }

    /// Checks the draft against the Recurring transaction rules before anything is saved.
    func validate() throws {
        guard !trimmedName.isEmpty else { throw RecurringRuleError.missingName }
        guard wallet != nil else { throw RecurringRuleError.missingWallet }
        guard amount.cents > 0 else { throw RecurringRuleError.missingAmount }
        guard category != nil else { throw RecurringRuleError.missingCategory }
        guard card == nil || card?.payingWallet == wallet else { throw RecurringRuleError.cardNotInWallet }
        switch end {
        case .forever:
            break
        case .until(let last):
            guard last >= startDay else { throw RecurringRuleError.untilBeforeStart }
        case .afterCount(let count):
            guard count >= 1 else { throw RecurringRuleError.noOccurrences }
        }
    }

    /// Whether every required field is filled, so Save can be enabled.
    var canSave: Bool { (try? validate()) != nil }
}

extension RecurringTransaction {
    /// Adds a Recurring transaction and saves it. Occurrences dated `today` or earlier are not made: the schedule
    /// starts from today on, as saving a past start date can't yet pick the ones to make. Saves.
    @discardableResult
    static func create(
        _ draft: RecurringDraft, today: CalendarDay = .today, in context: ModelContext
    ) throws -> RecurringTransaction {
        try draft.validate()
        let recurring = RecurringTransaction()
        context.insert(recurring)
        recurring.apply(draft)
        recurring.skipOccurrences(through: today)
        try context.save()
        return recurring
    }

    /// Saves an edited draft. Edits change only the occurrences still to come: nothing already made is touched.
    /// Nothing changes when the draft breaks a rule. Saves.
    func update(with draft: RecurringDraft, today: CalendarDay = .today) throws {
        try draft.validate()
        // What fell due under the old schedule is made under it first, before the edit reshapes what is still to come.
        if let context = modelContext {
            makeDueTransactions(through: today, in: context)
        }
        apply(draft)
        skipOccurrences(through: today)
        try modelContext?.save()
    }

    /// Removes the schedule, after making what has fallen due by `today` so no due day is lost. The transactions it
    /// made stay as ordinary transactions. Saves.
    func delete(today: CalendarDay = .today, in context: ModelContext) throws {
        makeDueTransactions(through: today, in: context)
        context.delete(self)
        try context.save()
    }

    /// Makes a transaction for each occurrence that has come due by `today` and hasn't been dealt with yet, then
    /// marks them dealt with, so each occurrence is made once however often this runs.
    func makeDueTransactions(through today: CalendarDay, in context: ModelContext) {
        guard let wallet = self.wallet, let category = self.category else { return }
        let due = schedule.occurrences(after: handledThrough, through: today)
        for day in due {
            let transaction = Transaction(
                amount: Money(cents: amountCents * category.sign, currencyCode: wallet.currencyCode),
                day: day,
                wallet: wallet,
                category: category,
                card: card,
                note: note
            )
            transaction.recurring = self
            context.insert(transaction)
        }
        if let last = due.last {
            handledThrough = last
        }
    }

    /// Marks the occurrences dated `today` or earlier as dealt with, without making them.
    func skipOccurrences(through today: CalendarDay) {
        if let last = schedule.occurrences(after: handledThrough, through: today).last {
            handledThrough = last
        }
    }

    /// The next day it makes a transaction on, or `nil` once the schedule has ended.
    var nextDueDay: CalendarDay? {
        schedule.nextOccurrence(after: handledThrough)
    }

    /// The transactions this schedule made, newest first. Those in Recently Deleted are left out.
    var attachedTransactions: [Transaction] {
        (transactions ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                lhs.dayRaw == rhs.dayRaw ? lhs.createdAt > rhs.createdAt : lhs.dayRaw > rhs.dayRaw
            }
    }

    /// Makes the transactions that have come due by `today`, for every Recurring transaction, and saves. The app runs
    /// this when it opens or comes back to the foreground, so the due days missed while it was closed are made then.
    static func catchUp(through today: CalendarDay = .today, in context: ModelContext) throws {
        for recurring in try context.fetch(FetchDescriptor<RecurringTransaction>()) {
            recurring.makeDueTransactions(through: today, in: context)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private func apply(_ draft: RecurringDraft) {
        name = draft.trimmedName
        amountCents = draft.amount.cents
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        wallet = draft.wallet
        category = draft.category
        card = draft.card
        kind = draft.kind
        schedule = draft.schedule
    }
}
