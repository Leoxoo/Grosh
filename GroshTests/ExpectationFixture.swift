import Foundation
import SwiftData
import Testing
@testable import Grosh

/// An in-memory store with Checking (the Month graph fixture's wallet) and a second wallet, Cash, for the Owes me tests.
/// It is seen on `today`, the 12th of October 2026.
@MainActor
struct ExpectationFixture {
    let store: MonthGraphFixture
    let cash: Wallet
    var context: ModelContext { store.context }
    var checking: Wallet { store.checking }
    var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
        cash = Wallet(name: "Cash")
        store.context.insert(cash)
    }

    func person(_ name: String) throws -> Person {
        try Person.add(named: name, in: context)
    }

    /// A dinner of `cents` under Restaurants in Checking, on the 3rd of October unless another day is given, saved as the
    /// Add sheet saves it: with `owing`, a + Owes me for each Person, with an amount or `nil` for an open amount.
    @discardableResult
    func dinner(
        _ cents: Int = 60_00, on date: CalendarDay? = nil, owing owes: [(person: Person, cents: Int?)] = []
    ) throws -> Transaction {
        var draft = TransactionDraft(type: .expense, day: date ?? day(2026, 10, 3))
        draft.wallet = checking
        draft.amount = Money(cents: cents)
        draft.category = try store.category("Restaurants")
        draft.people = owes.map(\.person)
        for owe in owes {
            draft.addOwes(owe.person)
            if let index = draft.owes.firstIndex(where: { $0.person === owe.person }) {
                draft.owes[index].amount = owe.cents.map { Money(cents: $0) }
            }
        }
        return try Transaction.create(draft, in: context)
    }

    /// The expectation `person` has on `expense`.
    func expectation(of person: Person, on expense: Transaction) throws -> ExpectedReimbursement {
        try #require(expense.orderedExpectations.first { $0.person === person })
    }

    /// Records a payment of `cents` on `expectation` on `date` (today unless given), into `wallet` (the Expense's own
    /// unless given).
    @discardableResult
    func pay(
        _ cents: Int, on expectation: ExpectedReimbursement, day date: CalendarDay? = nil, into wallet: Wallet? = nil,
        note: String = ""
    ) throws -> RecordedPayment {
        var draft = ExpectationPaymentDraft(paying: expectation, on: date ?? today)
        draft.amount = Money(cents: cents)
        if let wallet { draft.wallet = wallet }
        draft.note = note
        return try expectation.recordPayment(draft, in: context)
    }

    /// What the Report counts for `selection` in October.
    func totals(in selection: WalletSelection = .total) throws -> PeriodTotals {
        try PeriodTotals(
            of: store.transactions(), in: selection, period: .month(CalendarMonth(today)), today: today,
            otherIncome: store.otherIncome()
        )
    }

    /// Every Expected reimbursement the way Debts & Loans reads them.
    func owesMe() throws -> ExpectedReimbursements {
        try ExpectedReimbursements(in: context)
    }
}
