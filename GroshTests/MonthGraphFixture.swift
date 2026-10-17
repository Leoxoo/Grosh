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
        draft.withName = "Pasha"
        return try Transaction.create(draft, in: context)
    }

    /// Forgives what is outstanding on `loanOrDebt` on `day`, under Other Expense for a Loan or Other Income for a Debt.
    func forgive(_ loanOrDebt: Transaction, on day: CalendarDay) throws {
        try Forgiveness.record(ForgiveDraft(forgiving: loanOrDebt, on: day, in: context), in: context)
    }

    /// Every transaction in the store, those in Recently Deleted included.
    func transactions() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    /// The card for `side` showing `month`, this month unless another is given, compared with `choice`, made from every
    /// transaction and every Recurring transaction in the store, those in Recently Deleted included.
    func graph(
        _ side: SpentOrIncome, in month: CalendarMonth? = nil, comparingWith choice: MonthGraphComparison = .average
    ) throws -> MonthGraph {
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        return try MonthGraph(
            side, of: transactions(), recurring: recurring, in: month ?? CalendarMonth(today), today: today,
            comparingWith: choice
        )
    }
}
