import SwiftData
import Testing
@testable import Grosh

/// An in-memory store seeded with the default category tree and a Checking wallet, for Month graph tests. It is seen on
/// `today`, the 12th of a 31-day October, after a 30-day September and a year after another 31-day October.
@MainActor
struct MonthGraphFixture {
    let today = day(2026, 10, 12)
    private let categories: CategoryFixture
    var context: ModelContext { categories.context }
    var container: ModelContainer { categories.container }
    var checking: Wallet { categories.wallet }

    init() throws {
        categories = try CategoryFixture()
    }

    func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try categories.category(name, type)
    }

    /// Records `cents` (signed, as it moves the wallet) filed under `categoryName` on `day`, in Checking unless another
    /// wallet is given.
    @discardableResult
    func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, on day: CalendarDay,
        in wallet: Wallet? = nil
    ) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = wallet ?? checking
        transaction.category = try category(categoryName, type)
        return transaction
    }

    /// A Loan (`.loan`, money lent) or Debt (`.debt`, money borrowed) of `cents`, saved as the Add sheet's Debt/Loan tab
    /// saves it: left in the report, so only its category keeps it off the cards.
    @discardableResult
    func lendOrBorrow(_ role: LockedRole, _ cents: Int, on day: CalendarDay) throws -> Transaction {
        var draft = TransactionDraft(type: .debtLoan, day: day)
        draft.wallet = checking
        draft.amount = Money(cents: cents)
        draft.category = try context.lockedCategory(role)
        draft.people = [try Person.add(named: "Pasha", in: context)]
        return try Transaction.create(draft, in: context)
    }

    /// Forgives what is outstanding on `loanOrDebt` on `day`, under Other Expense for a Loan or Other Income for a Debt.
    func forgive(_ loanOrDebt: Transaction, on day: CalendarDay) throws {
        try Forgiveness.record(ForgiveDraft(forgiving: loanOrDebt, on: day, in: context), in: context)
    }

    /// The Other Income category, which a report reads once and counts an Expense paid back beyond its amount under.
    func otherIncome() throws -> Grosh.Category {
        try context.otherCategory(.income)
    }

    /// Every transaction in the store, those in Recently Deleted included.
    func transactions() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    /// The card for `side` showing `month`, this month unless another is given, compared with `choice`, as Home makes
    /// it: from what it reads from the store for that month (``MonthGraphHistory``) and every Recurring transaction,
    /// those in Recently Deleted included. Saves first, as the app has by the time Home reads.
    func graph(
        _ side: SpentOrIncome, in month: CalendarMonth? = nil, comparingWith choice: MonthGraphComparison = .average
    ) throws -> MonthGraph {
        let month = month ?? CalendarMonth(today)
        try context.save()
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        let history = try context.fetch(MonthGraphHistory.transactions(for: month))
            + context.fetch(MonthGraphHistory.forgiven)
        let otherIncome = try otherIncome()
        return try MonthGraph(
            side, of: history.compactMap { $0.countedAmount(otherIncome: otherIncome) }, countingFrom: firstDay(),
            recurring: recurring,
            in: .month(month), today: today, comparingWith: choice
        )
    }

    /// The months Home's strip offers, from what it reads from the store (``MonthGraphHistory``). Saves first.
    func strip() throws -> [Period] {
        try context.save()
        return try MonthGraph.months(from: firstDay(), today: today)
    }

    /// The first day anything counts on the Month graph, as Home reads it from the store.
    private func firstDay() throws -> CalendarDay? {
        try MonthGraphHistory.firstDay(
            earliest: context.fetch(MonthGraphHistory.earliestCounted), forgiven: context.fetch(MonthGraphHistory.forgiven),
            otherIncome: otherIncome()
        )
    }
}
