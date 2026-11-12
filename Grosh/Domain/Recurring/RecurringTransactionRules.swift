import Foundation
import SwiftData

/// Why a Recurring transaction can't be saved yet.
nonisolated enum RecurringRuleError: RuleRefusal, Equatable {
    case missingName
    case missingWallet
    /// The amount must be above zero, unless a varying Bill has an estimate to start from. The category sets the sign.
    case missingAmount
    case missingCategory
    /// A Card is only offered on its paying wallet's transactions, so it must be paid from the wallet chosen.
    case cardNotInWallet
    /// An end "until a date" must fall on or after the start date.
    case untilBeforeStart
    /// An end "after N times" needs at least one occurrence.
    case noOccurrences
    /// A Purchase's total price can't be worked out, as when it divides by zero.
    case invalidTotal
}

extension RecurringRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: Strings.Recurring.missingName)
        case .missingWallet: String(localized: Strings.Common.chooseAWallet)
        case .missingAmount: String(localized: Strings.Common.enterAmountAboveZero)
        case .missingCategory: String(localized: Strings.Common.chooseACategory)
        case .cardNotInWallet: String(localized: Strings.Recurring.cardNotInWallet)
        case .untilBeforeStart: String(localized: Strings.Recurring.untilBeforeStart)
        case .noOccurrences: String(localized: Strings.Recurring.noOccurrences)
        case .invalidTotal: String(localized: Strings.Common.enterAmountAboveZero)
        }
    }
}

/// Why a Recurring transaction can't make one now, with Add the Transaction.
nonisolated enum AddTransactionNowError: RuleRefusal, Equatable {
    /// A paused or deleted schedule makes nothing.
    case inactive
    /// A transaction needs a wallet and a category, which the schedule can lose when they are deleted.
    case incomplete
}

extension AddTransactionNowError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .inactive: String(localized: Strings.Recurring.inactive)
        case .incomplete: String(localized: Strings.Recurring.incomplete)
        }
    }
}

/// The editable fields of a Recurring transaction, as its form holds them before the rules check and save them.
nonisolated struct RecurringDraft {
    var name = ""
    /// The amount as typed, entered positive; the category sets the sign.
    var entry = AmountEntry()
    /// A Purchase's total price as typed. Left empty, or zero, it is no total. A Kind change keeps it, as it keeps the
    /// icon.
    var totalEntry = AmountEntry()
    /// Expense or Income. Switching it drops a category of the other type, and a name that only followed it.
    var type: CategoryType = .expense {
        didSet {
            if category?.type != type {
                pickedCategory = nil
            }
        }
    }
    /// Changing it drops the Card, which is only offered on its paying wallet's transactions.
    var wallet: Wallet? {
        didSet {
            if wallet !== oldValue {
                card = nil
            }
        }
    }
    var category: Category?
    /// The category as the form picks it. A Recurring transaction is named after its category until the user types a
    /// name of their own, and a new one (Add or Duplicate) takes the category's default Kind, which the user can change.
    var pickedCategory: Category? {
        get { category }
        set {
            let old = category
            category = newValue
            if name.isEmpty || name == old?.name {
                name = newValue?.name ?? ""
            }
            if isNew, let newValue {
                kind = newValue.defaultKind
            }
        }
    }
    var card: Card?
    /// The sort of Recurring transaction it is. A new one starts with its category's default Kind.
    var kind: RecurringKind = .regular {
        didSet {
            // A Purchase is paid off over time, so switching to one ends it after a number of payments,
            // which the user can then change.
            if kind == .purchase, oldValue != .purchase {
                endKind = .afterCount
            }
        }
    }
    /// Only a Bill's amount can vary: each transaction it makes then starts as an estimate, until the real amount is
    /// entered.
    var amountVaries = false
    /// For a varying Bill, how many days after an occurrence the user is reminded to enter its real amount.
    var remindAfterDays = 2
    /// The estimate last given with ``setEstimate(_:for:)``, and what it was read for.
    private var estimate: (request: EstimateRequest, cents: Int?)?
    /// Whether each transaction it makes would start Estimated: a Bill whose amount varies, as on the model.
    var estimatesAmount: Bool { kind.estimates(amountVaries: amountVaries) }
    var note = ""
    /// A Subscription's cropped icon, as JPEG data. It is kept while the Kind is something else, as on the model.
    var iconData: Data?
    /// The first occurrence. It may be in the past.
    var startDay: CalendarDay {
        didSet {
            // The last day is offered only from the 28th on, so a start moved below it drops a last day already picked.
            if !MonthlyDay.offered(startingOn: startDay).contains(monthlyDay) {
                monthlyDay = .sameDay
            }
        }
    }
    /// Which day of the month a monthly repeat falls on. Only the monthly repeats use it.
    var monthlyDay: MonthlyDay = .sameDay
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
    /// Where the schedule being edited started when the form opened, or `nil` for a new one.
    private var savedStart: CalendarDay?

    init(startDay: CalendarDay) {
        self.startDay = startDay
        untilDay = startDay.adding(days: 365)
    }

    init(editing recurring: RecurringTransaction) {
        let schedule = recurring.schedule
        self.init(startDay: schedule.start)
        name = recurring.name
        entry = AmountEntry(cents: recurring.amountCents)
        totalEntry = AmountEntry(cents: recurring.totalCents ?? 0)
        type = recurring.category?.type ?? .expense
        wallet = recurring.wallet
        category = recurring.category
        card = recurring.card
        kind = recurring.kind
        amountVaries = recurring.amountVaries
        remindAfterDays = recurring.remindAfterDays
        note = recurring.note
        iconData = recurring.iconData
        preset = RepeatPreset(rule: schedule.rule)
        customRule = schedule.rule
        monthlyDay = schedule.monthlyDay
        end = schedule.end
        savedStart = schedule.start
    }

    /// What a varying Bill's estimate is read for: its category's history in its wallet's currency (``AmountEstimate``).
    struct EstimateRequest: Equatable {
        let category: Category
        let currencyCode: String
    }

    /// The estimate the draft needs now, or `nil` when its amount doesn't vary or it has no category yet. The draft
    /// reads nothing from the store: whoever holds it reads the estimate from ``AmountEstimate`` and gives it with
    /// ``setEstimate(_:for:)`` whenever this changes.
    var neededEstimate: EstimateRequest? {
        guard estimatesAmount, let category else { return nil }
        return EstimateRequest(category: category, currencyCode: currencyCode)
    }

    /// Gives the draft the estimate read for `request`: `cents`, or `nil` when the category has no history to average.
    mutating func setEstimate(_ cents: Int?, for request: EstimateRequest) {
        estimate = (request, cents)
    }

    /// The average a varying Bill's transactions would start at, or `nil` when there is none or the amount doesn't
    /// vary. It stands in for an amount left empty, and is never saved. An estimate given for another category,
    /// currency or Kind than the draft now has counts as none.
    var estimateCents: Int? {
        guard let request = neededEstimate, let estimate, estimate.request == request else { return nil }
        return estimate.cents
    }

    /// A new Recurring transaction like `recurring`, starting `today` ("Duplicate"). It copies every field and the Kind's
    /// settings, the icon, Bill and Purchase settings included, but none of the transactions attached to it, so a
    /// Purchase's progress starts over.
    init(duplicating recurring: RecurringTransaction, on today: CalendarDay) {
        self.init(editing: recurring)
        savedStart = nil
        startDay = today
        // A last day already past can't end a schedule that starts today, so the copy gets a year, as a new one does.
        if endKind == .until, untilDay < today {
            untilDay = today.adding(days: 365)
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The amounts are in the wallet's currency.
    var currencyCode: String { wallet.currencyCodeOrDefault }

    /// A Purchase's total price, or `nil` for none: a total left empty or typed as zero is none.
    var total: Money? {
        get {
            guard let cents = totalEntry.cents, cents > 0 else { return nil }
            return Money(cents: cents, currencyCode: currencyCode)
        }
        set { totalEntry = AmountEntry(cents: newValue?.cents ?? 0) }
    }

    /// Whether it saves a new Recurring transaction, as Add and Duplicate do, rather than changing one.
    var isNew: Bool { savedStart == nil }

    /// Whether saving offers the occurrences that have already come due: for a new schedule, or one whose start day has
    /// moved.
    var offersPastOccurrences: Bool { savedStart != startDay }

    /// The repeat the form has picked.
    var rule: RepeatRule { preset.rule ?? customRule }

    /// When the Recurring transaction ends, as the form has it. Setting it sets the form's end and its day or count.
    var end: RepeatEnd {
        get {
            switch endKind {
            case .forever: .forever
            case .until: .until(untilDay)
            case .afterCount: .afterCount(occurrenceCount)
            }
        }
        set {
            endKind = newValue.kind
            switch newValue {
            case .forever: break
            case .until(let last): untilDay = last
            case .afterCount(let count): occurrenceCount = count
            }
        }
    }

    /// When the Recurring transaction falls due, as the form has it.
    var schedule: RepeatSchedule {
        RepeatSchedule(start: startDay, rule: rule, end: end, monthlyDay: monthlyDay)
    }

    func validate() throws {
        guard !trimmedName.isEmpty else { throw RecurringRuleError.missingName }
        guard wallet != nil else { throw RecurringRuleError.missingWallet }
        // A varying Bill may leave its amount empty when there is an estimate to start its transactions from.
        let startsFromEstimate = estimatesAmount && estimateCents != nil
        guard amount.cents > 0 || startsFromEstimate else { throw RecurringRuleError.missingAmount }
        guard totalEntry.cents != nil else { throw RecurringRuleError.invalidTotal }
        guard category != nil else { throw RecurringRuleError.missingCategory }
        guard card == nil || card?.payingWallet === wallet else { throw RecurringRuleError.cardNotInWallet }
        switch end {
        case .forever:
            break
        case .until(let last):
            guard last >= startDay else { throw RecurringRuleError.untilBeforeStart }
        case .afterCount(let count):
            guard count >= 1 else { throw RecurringRuleError.noOccurrences }
        }
    }
}

extension RecurringTransaction {
    /// Adds a Recurring transaction. Occurrences dated `today` or earlier are not made here: they are skipped, and the
    /// editor's start-date prompt offers them (``unenteredOccurrences(through:)``). Saves.
    @discardableResult
    @MainActor
    static func create(
        _ draft: RecurringDraft, today: CalendarDay, in context: ModelContext
    ) throws -> RecurringTransaction {
        try draft.validate()
        let recurring = RecurringTransaction()
        context.insert(recurring)
        recurring.apply(draft)
        recurring.skipOccurrences(through: today)
        try context.save()
        return recurring
    }

    /// Edits change only the occurrences still to come: nothing already made is touched. Saves.
    @MainActor
    func update(with draft: RecurringDraft, today: CalendarDay) throws {
        try draft.validate()
        let context = try storeContext()
        // What fell due under the old schedule is made under it first, before the edit reshapes what is still to come.
        try makeDueTransactions(through: today)
        apply(draft)
        skipOccurrences(through: today)
        try context.save()
    }

    /// Moves the schedule to Recently Deleted, after making what has fallen due by `today` so no due day is lost. The
    /// transactions it made stay as ordinary transactions: they lose their link to it. Saves.
    @MainActor
    func delete(today: CalendarDay, at now: Date = .now) throws {
        let context = try storeContext()
        try makeDueTransactions(through: today)
        deletedAt = now
        for transaction in transactions ?? [] {
            transaction.recurring = nil
        }
        try context.save()
    }

    /// Makes a transaction for each occurrence that has come due by `today` and hasn't been dealt with yet, then
    /// marks them dealt with, so each occurrence is made once however often this runs. A schedule that is deleted or
    /// paused makes none.
    func makeDueTransactions(through today: CalendarDay) throws {
        guard isActive, wallet != nil, category != nil else { return }
        let due = schedule.occurrences(after: handledThrough, through: today)
        guard !due.isEmpty else { return }
        let estimate = currentEstimateCents()
        for day in due {
            try makeTransaction(on: day, estimateCents: estimate)
        }
        if let last = due.last {
            handledThrough = last
        }
    }

    /// The estimate a varying Bill's transactions start at now: the average ``AmountEstimate`` gives for its category
    /// and wallet currency, read from the store. `nil` for other Kinds, and when there is nothing to average.
    func currentEstimateCents() -> Int? {
        guard estimatesAmount, let category = self.category, let wallet = self.wallet else { return nil }
        return AmountEstimate.cents(for: category, currencyCode: wallet.currencyCode)
    }

    /// What each transaction it makes is for, signed by its category: `estimateCents` (``currentEstimateCents()``)
    /// when there is one, otherwise the typed amount. Making a transaction and showing the schedule both use it, so a
    /// varying Bill's rows show the amount its transactions will hold.
    func startingAmount(estimateCents: Int?) -> Money {
        Money(cents: (estimateCents ?? amountCents) * (category?.sign ?? -1), currencyCode: currencyCode)
    }

    /// What its transactions start at now, a varying Bill's estimate read from the store. A screen showing many
    /// schedules reads them once through ``RecurringFigures``.
    func currentStartingAmount() -> Money {
        startingAmount(estimateCents: currentEstimateCents())
    }

    /// Makes the transaction for the occurrence on `day`, attached to this schedule, and inserts it. A Bill whose amount
    /// varies starts Estimated, at `estimateCents` (``currentEstimateCents()``). Nothing is made without a wallet and a
    /// category, which the schedule can lose when they are deleted.
    @discardableResult
    func makeTransaction(on day: CalendarDay, estimateCents: Int?) throws -> Transaction? {
        guard let wallet = self.wallet, let category = self.category else { return nil }
        let transaction = Transaction.insert(
            cents: startingAmount(estimateCents: estimateCents).cents, on: day, wallet: wallet, category: category,
            card: card, note: note, in: try storeContext()
        )
        transaction.recurring = self
        if estimatesAmount {
            transaction.isEstimated = true
            transaction.estimateReminderDay = day.adding(days: remindAfterDays)
        }
        return transaction
    }

    /// The occurrences from the start day through `today` that have no transaction yet, in order: what the start-date
    /// prompt offers. Any transaction of this schedule counts, Recently Deleted ones included, so a restored one never
    /// doubles up with a day offered again.
    func unenteredOccurrences(through today: CalendarDay) -> [CalendarDay] {
        let entered = Set((transactions ?? []).map(\.dayRaw))
        return schedule.occurrences(after: nil, through: today).filter { !entered.contains($0.rawValue) }
    }

    /// Makes a transaction on each of `days`, the occurrences the user picked from the start-date prompt, and saves.
    /// Nothing is made for an empty list.
    func makeTransactions(on days: [CalendarDay]) throws {
        let context = try storeContext()
        let estimate = currentEstimateCents()
        for day in days {
            try makeTransaction(on: day, estimateCents: estimate)
        }
        try context.save()
    }

    /// Why Add the Transaction can't make one now, or `nil` when it can: the schedule is paused or deleted, or has no
    /// wallet or category to make it with.
    var addBlocker: AddTransactionNowError? {
        guard isActive else { return .inactive }
        guard wallet != nil, category != nil else { return .incomplete }
        return nil
    }

    /// Whether Add the Transaction can make one now, see ``addBlocker``.
    var canAddTransactionNow: Bool { addBlocker == nil }

    /// Makes one transaction now, dated `today`, from the schedule's values, and attaches it. Unlike an occurrence it
    /// consumes or skips nothing: the next occurrence still falls on its day. Throws its ``addBlocker`` rather than
    /// saving nothing. Saves.
    @MainActor
    func addTransactionNow(today: CalendarDay) throws {
        if let addBlocker { throw addBlocker }
        let context = try storeContext()
        try makeTransaction(on: today, estimateCents: currentEstimateCents())
        try context.save()
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

    /// The transactions this schedule made or the user attached, newest first. Those in Recently Deleted are left out.
    var attachedTransactions: [Transaction] {
        (transactions ?? [])
            .filter { $0.deletedAt == nil }
            .inListOrder()
    }

    /// Every Recurring transaction outside Recently Deleted, in the order they were added: what Account → Recurring
    /// transactions lists.
    static var notDeleted: FetchDescriptor<RecurringTransaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)])
    }

    /// Makes the transactions that have come due by `today`, for every Recurring transaction, and saves. The app runs
    /// this when it opens or comes back to the foreground, so the due days missed while it was closed are made then.
    @MainActor
    static func catchUp(through today: CalendarDay, in context: ModelContext) throws {
        for recurring in try context.fetch(FetchDescriptor<RecurringTransaction>()) {
            try recurring.makeDueTransactions(through: today)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private func apply(_ draft: RecurringDraft) {
        name = draft.trimmedName
        amountCents = draft.amount.cents
        totalCents = draft.total?.cents
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        wallet = draft.wallet
        category = draft.category
        card = draft.card
        kind = draft.kind
        iconData = draft.iconData
        amountVaries = draft.amountVaries
        remindAfterDays = draft.remindAfterDays
        schedule = draft.schedule
    }
}
