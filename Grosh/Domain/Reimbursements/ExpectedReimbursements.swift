import Foundation
import SwiftData

/// Why an Expected reimbursement can't be saved, paid, closed or forgiven.
nonisolated enum ExpectedReimbursementRuleError: Error, Equatable {
    /// Only an Expense can have Owes me.
    case notAnExpense
    /// Owes me is for a Person in With; this one (by name) was taken out.
    case personNotInWith(String)
    /// An amount to pay back must be above zero; leave it blank when it isn't known yet.
    case invalidAmount
    /// People can't owe more together than the Expense cost.
    case amountAboveExpense
    /// Money has been paid back against it (the Person's name), so it can't be removed.
    case hasPayments(String)
    /// Nothing is expected any more: it was paid back, closed or forgiven.
    case notOpen
    /// Only an expectation with no amount is closed by hand; one with an amount closes itself once paid.
    case hasAnAmount
    /// Only a closed expectation is reopened.
    case notClosed
    /// Only a forgiven expectation can be un-forgiven.
    case notForgiven
    /// An Expense with money paid back into another wallet stays in its wallet.
    case walletLockedByPaybacks
    /// A part of a Split can't be paid back into another wallet: the parts are independent (ADR-0007).
    case splitPart
}

extension ExpectedReimbursementRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notAnExpense:
            String(localized: "Only an Expense can have Owes me.")
        case .personNotInWith(let name):
            String(localized: "\(name) still owes you for this Expense. Put \(name) back in With, or remove Owes me first.")
        case .invalidAmount:
            String(localized: "Enter an amount above zero, or leave it blank if you don't know it yet.")
        case .amountAboveExpense:
            String(localized: "People can't owe you more than the Expense cost.")
        case .hasPayments(let name):
            String(localized: "\(name) has paid some of this back, so it can't be removed.")
        case .notOpen:
            String(localized: "Nothing is expected any more.")
        case .hasAnAmount:
            String(localized: "Only an expectation with no amount is closed by hand. One with an amount closes itself once it is paid.")
        case .notClosed:
            String(localized: "It isn't closed.")
        case .notForgiven:
            String(localized: "It isn't forgiven.")
        case .walletLockedByPaybacks:
            String(localized: "Money was paid back into another wallet against this Expense, so it stays in its wallet.")
        case .splitPart:
            String(localized: "A part of a Split can't be paid back into another wallet.")
        }
    }
}

/// Where an Expected reimbursement stands.
nonisolated enum ExpectationStatus: Hashable, Sendable {
    /// Something is still expected.
    case open
    /// Payments cover what was expected.
    case paidBack
    /// Closed by hand, for an open amount.
    case closed
    /// Forgiven: the money won't come back (ADR-0004).
    case forgiven
}

/// One payment recorded against an Expected reimbursement, whichever way it was kept.
struct ExpectationPayment: Identifiable {
    let id: PersistentIdentifier
    let amount: Money
    let day: CalendarDay
    let note: String
    /// The wallet the money came into.
    let wallet: Wallet?
    /// Whether it came into another wallet than the Expense's, so it is a transaction of its own (ADR-0010) rather than a
    /// Reimbursement on the Expense (ADR-0008).
    let isElsewhere: Bool
}

extension ExpectedReimbursement {
    /// How many days after its Expense an expectation reminds the user, to begin with.
    static let reminderDays = 7

    /// The day a new expectation's reminder starts at: a week after its Expense's day, not after today, since the
    /// Expense may be old.
    static func defaultReminderDay(expenseOn day: CalendarDay) -> CalendarDay {
        day.adding(days: reminderDays)
    }

    /// The currency of the Expense's wallet.
    var currencyCode: String { expense?.amount.currencyCode ?? Money.defaultCurrencyCode }

    /// What is expected, or `nil` for an open amount.
    var expected: Money? { amountCents.map { Money(cents: $0, currencyCode: currencyCode) } }

    /// Whether the amount isn't known yet, shown as `?`. Left out of totals.
    var hasOpenAmount: Bool { amountCents == nil }

    var reminderDay: CalendarDay? {
        get { reminderDayRaw.map(CalendarDay.init(rawValue:)) }
        set { reminderDayRaw = newValue?.rawValue }
    }

    /// The day it was forgiven, or `nil` while it isn't.
    var forgivenDay: CalendarDay? {
        get { forgivenDayRaw.map(CalendarDay.init(rawValue:)) }
        set { forgivenDayRaw = newValue?.rawValue }
    }

    /// The day it was closed by hand, or `nil` while it isn't.
    var closedDay: CalendarDay? {
        get { closedDayRaw.map(CalendarDay.init(rawValue:)) }
        set { closedDayRaw = newValue?.rawValue }
    }

    /// The payments recorded against it, earliest day first: Reimbursements on the Expense and paybacks into other
    /// wallets. A payback in Recently Deleted is not among them.
    var payments: [ExpectationPayment] {
        let sameWallet = (reimbursements ?? []).map { entry in
            ExpectationPayment(
                id: entry.persistentModelID, amount: entry.amount, day: entry.day, note: entry.note,
                wallet: expense?.wallet, isElsewhere: false
            )
        }
        let elsewhere = (paybacks ?? []).filter { !$0.isInRecentlyDeleted }.map { payback in
            ExpectationPayment(
                id: payback.persistentModelID, amount: payback.amount, day: payback.day, note: payback.note,
                wallet: payback.wallet, isElsewhere: true
            )
        }
        return (sameWallet + elsewhere).sorted { $0.day < $1.day }
    }

    /// What has been paid back so far, whichever wallet it came into.
    var paid: Money {
        let sameWallet = (reimbursements ?? []).reduce(0) { $0 + $1.amountCents }
        let elsewhere = (paybacks ?? []).filter { !$0.isInRecentlyDeleted }.reduce(0) { $0 + $1.amountCents }
        return Money(cents: sameWallet + elsewhere, currencyCode: currencyCode)
    }

    /// Whether any money was ever recorded against it, a payback in Recently Deleted included: such an expectation can't
    /// be removed.
    var hasPayments: Bool { !(reimbursements ?? []).isEmpty || !(paybacks ?? []).isEmpty }

    /// Where it stands. Forgiven or closed by hand wins over everything; otherwise an expectation with an amount is paid
    /// back once its payments cover it, and one with no amount stays open until it is closed.
    var status: ExpectationStatus {
        if forgivenDayRaw != nil { return .forgiven }
        if closedDayRaw != nil { return .closed }
        if let amountCents, paid.cents >= amountCents { return .paidBack }
        return .open
    }

    /// Whether something is still expected.
    var isOpen: Bool { status == .open }

    /// How much is still to come: the amount less the payments, never below zero, and nothing once it is settled. `nil`
    /// for an open amount, which is not known.
    var outstanding: Money? {
        guard let amountCents else { return nil }
        let cents = isOpen ? max(0, amountCents - paid.cents) : 0
        return Money(cents: cents, currencyCode: currencyCode)
    }

    /// Whether the Expense is outside Recently Deleted. The expectations of one in the bin are in the bin with it.
    var isOfLiveExpense: Bool { expense.map { !$0.isInRecentlyDeleted } ?? false }

    /// What the Expense was, for a row or a notification: its note, else its category's name.
    var expenseTitle: String {
        guard let expense else { return "" }
        return expense.note.isEmpty ? expense.categoryName : expense.note
    }

    /// The Person's name.
    var personName: String { person?.name ?? "" }
}

// MARK: Changing it

extension ExpectedReimbursement {
    /// Moves or clears the reminder day, whatever has been paid. Saves.
    func setReminder(_ day: CalendarDay?) throws {
        reminderDay = day
        try modelContext?.save()
    }

    /// Closes an open-amount expectation by hand on `day`: nothing more is expected. Saves.
    func close(on day: CalendarDay = .today) throws {
        guard isOpen else { throw ExpectedReimbursementRuleError.notOpen }
        guard hasOpenAmount else { throw ExpectedReimbursementRuleError.hasAnAmount }
        closedDay = day
        try modelContext?.save()
    }

    /// Opens a closed expectation again. Saves.
    func reopen() throws {
        guard closedDayRaw != nil else { throw ExpectedReimbursementRuleError.notClosed }
        closedDay = nil
        try modelContext?.save()
    }

    /// Forgive: the money won't come back. It is marked Forgiven on `day` with an optional note and counts as settled
    /// (ADR-0004). No transaction is added and nothing in any balance or report changes, since an expectation never
    /// counted in either. Saves.
    func forgive(on day: CalendarDay = .today, note: String = "") throws {
        guard isOpen else { throw ExpectedReimbursementRuleError.notOpen }
        forgivenDay = day
        forgivenNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try modelContext?.save()
    }

    /// Takes the Forgiven mark off, so it is open again if anything is still expected. Saves.
    func unforgive() throws {
        guard forgivenDayRaw != nil else { throw ExpectedReimbursementRuleError.notForgiven }
        forgivenDay = nil
        forgivenNote = ""
        try modelContext?.save()
    }
}

// MARK: Owes me on an Expense

/// What the Add Transaction sheet holds for one + Owes me: the Person, an optional amount (blank is an open amount) and
/// the reminder day.
struct OwesMeDraft {
    let person: Person
    /// Entered positive, or `nil` while blank: an open amount.
    var amount: Money?
    /// On by default, a week after the Expense. `nil` switches it off.
    var reminderDay: CalendarDay?
    /// The expectation being edited, or `nil` for a new one.
    private(set) var existing: ExpectedReimbursement?
    /// Whether money was already paid back against the one being edited, so it can't be removed.
    private(set) var hasPayments = false

    /// A new expectation for `person` on an Expense dated `expenseDay`.
    init(person: Person, expenseDay: CalendarDay) {
        self.person = person
        reminderDay = ExpectedReimbursement.defaultReminderDay(expenseOn: expenseDay)
    }

    /// `expectation` as it is, to edit. `nil` for one whose Person is gone.
    init?(editing expectation: ExpectedReimbursement) {
        guard let person = expectation.person else { return nil }
        self.person = person
        amount = expectation.expected
        reminderDay = expectation.reminderDay
        existing = expectation
        hasPayments = expectation.hasPayments
    }
}

extension Transaction {
    /// Its Expected reimbursements, the earliest made first.
    var orderedExpectations: [ExpectedReimbursement] {
        (expectations ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Makes the expectations of this Expense match `entries`: a new one for each entry with no `existing`, the others
    /// changed to the entry, and any not among the entries removed. Whether that is allowed is
    /// ``TransactionDraft/validate()``'s to check. Doesn't save, and moves no balance or report.
    func setExpectations(_ entries: [OwesMeDraft]) {
        guard let context = modelContext else { return }
        for existing in expectations ?? [] where !entries.contains(where: { $0.existing === existing }) {
            expectations?.removeAll { $0 === existing }
            context.delete(existing)
        }
        for entry in entries {
            let expectation: ExpectedReimbursement
            if let existing = entry.existing {
                expectation = existing
            } else {
                expectation = ExpectedReimbursement()
                context.insert(expectation)
                expectation.expense = self
                expectation.person = entry.person
            }
            expectation.amountCents = entry.amount?.cents
            expectation.reminderDay = entry.reminderDay
        }
    }
}

extension TransactionDraft {
    /// Whether the Add sheet offers + Owes me: only on an ordinary Expense.
    var offersOwesMe: Bool {
        type == .expense && offersCard && !isBalanceAdjustment
    }

    /// The + Owes me for `person`, or `nil` when there is none.
    func owesEntry(for person: Person) -> OwesMeDraft? {
        owes.first { $0.person === person }
    }

    /// Adds + Owes me for `person`, with no amount and a reminder a week after the Expense. Does nothing when there is
    /// one already.
    mutating func addOwes(_ person: Person) {
        guard owesEntry(for: person) == nil else { return }
        owes.append(OwesMeDraft(person: person, expenseDay: day))
    }

    /// Takes + Owes me off `person`. One with money paid back against it stays: its payments are on the Expense.
    mutating func removeOwes(_ person: Person) {
        owes.removeAll { $0.person === person && !$0.hasPayments }
    }

    /// Checks + Owes me against the Expense as the draft has it: it must stay an Expense, every Person owing must still
    /// be in With, the amounts must be above zero and together no more than the Expense, an expectation with payments
    /// stays, and an Expense paid back into another wallet stays in its wallet.
    func validateExpectations() throws {
        for original in originalExpectations
        where !owes.contains(where: { $0.existing === original }) && original.hasPayments {
            throw ExpectedReimbursementRuleError.hasPayments(original.personName)
        }
        if let walletKeptByPaybacks, wallet !== walletKeptByPaybacks {
            throw ExpectedReimbursementRuleError.walletLockedByPaybacks
        }
        guard !owes.isEmpty else { return }
        guard offersOwesMe else { throw ExpectedReimbursementRuleError.notAnExpense }
        var total = 0
        for entry in owes {
            guard people.contains(where: { $0 === entry.person }) else {
                throw ExpectedReimbursementRuleError.personNotInWith(entry.person.name)
            }
            if let cents = entry.amount?.cents {
                guard cents > 0 else { throw ExpectedReimbursementRuleError.invalidAmount }
                guard cents <= amount.cents else { throw ExpectedReimbursementRuleError.amountAboveExpense }
                total += cents
            }
        }
        guard total <= amount.cents else { throw ExpectedReimbursementRuleError.amountAboveExpense }
    }
}

// MARK: Listing them

/// What Debts & Loans, the Home bell and the reminders read of Owes me: every Expected reimbursement whose Expense is
/// outside Recently Deleted, split into the open ones and the settled ones (ADR-0010).
struct ExpectedReimbursements {
    /// Expectations with something still expected: those with a reminder day first, the soonest first, then the rest,
    /// the oldest Expense first.
    let open: [ExpectedReimbursement]
    /// Expectations paid back, closed or forgiven, the newest Expense first.
    let settled: [ExpectedReimbursement]

    /// Every Expected reimbursement in the store. The ones of an Expense in Recently Deleted are left out by
    /// ``init(_:)``, which reads the Expense's ``Transaction/deletedAt``, so a screen showing them follows the Expense
    /// going to the bin and coming back.
    static var all: FetchDescriptor<ExpectedReimbursement> {
        FetchDescriptor()
    }

    init(_ expectations: some Sequence<ExpectedReimbursement>) {
        let live = expectations.filter(\.isOfLiveExpense)
        open = live.filter(\.isOpen).sorted { Self.isDue(before: $0, $1) }
        settled = live.filter { !$0.isOpen }.sorted { Self.isNewer($0, than: $1) }
    }

    /// Every Expected reimbursement in `context`.
    init(in context: ModelContext) throws {
        self.init(try context.fetch(Self.all))
    }

    /// Whether `first` comes before `second` among the open ones: a reminder day before none, an earlier reminder day
    /// before a later one, and otherwise the older Expense first.
    private static func isDue(before first: ExpectedReimbursement, _ second: ExpectedReimbursement) -> Bool {
        switch (first.reminderDay, second.reminderDay) {
        case let (firstDay?, secondDay?) where firstDay != secondDay: return firstDay < secondDay
        case (.some, nil): return true
        case (nil, .some): return false
        default: return isOlder(first, than: second)
        }
    }

    private static func isOlder(_ first: ExpectedReimbursement, than second: ExpectedReimbursement) -> Bool {
        (first.expense?.dayRaw ?? 0, first.createdAt) < (second.expense?.dayRaw ?? 0, second.createdAt)
    }

    private static func isNewer(_ first: ExpectedReimbursement, than second: ExpectedReimbursement) -> Bool {
        isOlder(second, than: first)
    }

    /// What the open ones come to: the outstanding amounts and how many have no amount.
    var totals: ExpectationTotals { ExpectationTotals(open) }

    /// The open expectations whose reminder day is `today` or earlier, the earliest first: what the Home bell lists. A
    /// settled one is never due.
    func due(on today: CalendarDay) -> [ExpectedReimbursement] {
        open.filter { $0.reminderDay.map { $0 <= today } ?? false }
            .sorted { $0.reminderDay ?? today < $1.reminderDay ?? today }
    }

    /// The expectations grouped by Person, for Show by people: each Person with their open and settled expectations and
    /// what they still owe in each currency. People with something open come first, the one owing most first, then by
    /// name. Read from the expectations at hand in one pass; nothing is fetched.
    var byPerson: [PersonExpectations] {
        var order: [ObjectIdentifier] = []
        var people: [ObjectIdentifier: Person] = [:]
        var grouped: [ObjectIdentifier: [ExpectedReimbursement]] = [:]
        for expectation in open + settled {
            guard let person = expectation.person else { continue }
            let key = ObjectIdentifier(person)
            if people[key] == nil {
                order.append(key)
                people[key] = person
            }
            grouped[key, default: []].append(expectation)
        }
        return order.compactMap { key in
            people[key].map { PersonExpectations(person: $0, expectations: grouped[key] ?? []) }
        }
        .sorted { $0.isListed(before: $1) }
    }
}

/// What a set of open expectations come to: the outstanding amounts per currency, and how many are open-amount ones,
/// which are left out of the amounts and flagged ("+1 open").
struct ExpectationTotals: Equatable {
    /// What is outstanding on the open expectations that have an amount, one total per currency, by currency code.
    let outstanding: [Money]
    /// How many open expectations have no amount.
    let openAmountCount: Int

    init(_ expectations: some Sequence<ExpectedReimbursement>) {
        var cents: [String: Int] = [:]
        var unknown = 0
        for expectation in expectations where expectation.isOpen {
            if let outstanding = expectation.outstanding {
                cents[outstanding.currencyCode, default: 0] += outstanding.cents
            } else {
                unknown += 1
            }
        }
        outstanding = cents.keys.sorted().map { Money(cents: cents[$0] ?? 0, currencyCode: $0) }
        openAmountCount = unknown
    }
}

/// One Person's expectations, as Show by people lists them.
struct PersonExpectations: Identifiable {
    let person: Person
    /// Open ones first, then the settled ones, in the order ``ExpectedReimbursements`` lists them.
    let expectations: [ExpectedReimbursement]

    var id: PersistentIdentifier { person.persistentModelID }

    /// The expectations with something still expected.
    var open: [ExpectedReimbursement] { expectations.filter(\.isOpen) }

    /// What the Person still owes, and how many open expectations have no amount.
    var totals: ExpectationTotals { ExpectationTotals(expectations) }

    /// Whether the Person is listed before `other`: someone owing something before someone owing nothing known, the one
    /// owing more first (by their largest currency total), and otherwise by name.
    fileprivate func isListed(before other: PersonExpectations) -> Bool {
        let mine = totals
        let theirs = other.totals
        let myOpen = !mine.outstanding.isEmpty || mine.openAmountCount > 0
        let theirOpen = !theirs.outstanding.isEmpty || theirs.openAmountCount > 0
        if myOpen != theirOpen { return myOpen }
        let myLargest = mine.outstanding.map(\.cents).max() ?? 0
        let theirLargest = theirs.outstanding.map(\.cents).max() ?? 0
        if myLargest != theirLargest { return myLargest > theirLargest }
        return person.name.localizedStandardCompare(other.person.name) == .orderedAscending
    }
}
