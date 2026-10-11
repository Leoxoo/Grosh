import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Purchases: their optional total, the progress their attached transactions show, the payments that count toward it,
/// and what a payment is prefilled from.
@MainActor
struct PurchaseProgressTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func category(_ name: String, _ type: CategoryType) -> Grosh.Category {
        let category = Grosh.Category(name: name, type: type, symbolName: "repeat", color: .purple)
        context.insert(category)
        return category
    }

    /// A laptop paid for in monthly payments of 100.00 from `start`, with `total` as its price (`nil` for none).
    private func laptop(
        total: Int?, starting start: CalendarDay = CalendarDay(year: 2026, month: 9, day: 1)
    ) -> RecurringDraft {
        var draft = RecurringDraft(startDay: start)
        draft.name = "Laptop"
        draft.amount = Money(cents: 10_000)
        draft.wallet = store.wallet
        draft.category = category("Shopping", .expense)
        draft.kind = .purchase
        draft.total = total.map { Money(cents: $0) }
        return draft
    }

    /// An earlier payment of `cents` from the fixture's wallet, attached to `recurring`.
    @discardableResult
    private func attachPayment(_ cents: Int, dated: CalendarDay, to recurring: RecurringTransaction) throws -> Transaction {
        let payment = Transaction(amount: Money(cents: -cents), day: dated, wallet: store.wallet, category: nil)
        context.insert(payment)
        try recurring.attach(payment, in: context)
        return payment
    }

    @Test func aNewPurchaseEndsAfterNPaymentsUnlessTheUserChoosesOtherwise() {
        var draft = RecurringDraft(startDay: today)
        #expect(draft.endKind == .forever)

        draft.kind = .purchase
        #expect(draft.endKind == .afterCount)

        draft.endKind = .forever
        draft.kind = .purchase
        #expect(draft.endKind == .forever)

        draft.kind = .regular
        draft.kind = .purchase
        #expect(draft.endKind == .afterCount)
    }

    @Test func aPurchaseWithATotalShowsWhatHasBeenPaidOfIt() throws {
        let recurring = try RecurringTransaction.create(laptop(total: 120_000), today: today, in: context)
        // An earlier payment and the schedule's own payment both count as paid.
        try attachPayment(30_000, dated: day(2026, 9, 1), to: recurring)
        try RecurringTransaction.catchUp(through: day(2026, 11, 1), in: context)

        let progress = try #require(recurring.purchaseProgress)
        #expect(progress.total?.cents == 120_000)
        #expect(progress.paid.cents == 40_000)
    }

    @Test func aPurchaseWithoutATotalShowsOnlyWhatHasBeenPaid() throws {
        let recurring = try RecurringTransaction.create(laptop(total: nil), today: today, in: context)
        try attachPayment(30_000, dated: day(2026, 9, 1), to: recurring)

        let progress = try #require(recurring.purchaseProgress)
        #expect(progress.total == nil)
        #expect(progress.paid.cents == 30_000)
    }

    @Test func aPaymentInRecentlyDeletedDoesNotCountAsPaid() throws {
        let recurring = try RecurringTransaction.create(laptop(total: 120_000), today: today, in: context)
        let payment = try attachPayment(30_000, dated: day(2026, 9, 1), to: recurring)
        payment.deletedAt = Date.now

        #expect(try #require(recurring.purchaseProgress).paid.cents == 0)
    }

    @Test func otherKindsShowNoProgress() throws {
        var draft = laptop(total: 120_000)
        draft.kind = .bill
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        #expect(recurring.purchaseProgress == nil)
    }

    /// The payments a Purchase attaches don't use up its scheduled ones: all three are still made.
    @Test func attachedPaymentsDoNotUseUpTheScheduledOnes() throws {
        var draft = laptop(total: nil, starting: day(2026, 10, 12))
        draft.occurrenceCount = 3
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)
        try attachPayment(30_000, dated: day(2026, 9, 1), to: recurring)

        try RecurringTransaction.catchUp(through: day(2026, 12, 31), in: context)

        #expect(recurring.attachedTransactions.count == 4)
        #expect(recurring.nextDueDay == nil)
    }

    @Test func theTotalIsKeptWhenTheKindChangesButOnlyAPurchaseShowsIt() throws {
        let recurring = try RecurringTransaction.create(laptop(total: 120_000), today: today, in: context)
        #expect(recurring.totalCents == 120_000)

        var edited = RecurringDraft(editing: recurring)
        #expect(edited.total?.cents == 120_000)
        edited.kind = .bill
        try recurring.update(with: edited, today: today)

        #expect(recurring.totalCents == 120_000)
        #expect(recurring.purchaseProgress == nil)
    }

    @Test func aPaymentIsPrefilledFromThePurchaseAndDatedToday() throws {
        let recurring = try RecurringTransaction.create(laptop(total: 120_000), today: today, in: context)

        let draft = TransactionDraft(paymentFor: recurring, on: today)

        #expect(draft.amount.cents == 10_000)
        #expect(draft.wallet == store.wallet)
        #expect(draft.category == recurring.category)
        #expect(draft.type == .expense)
        #expect(draft.day == today)
    }

    /// A copy keeps the total, which is the Purchase's price, but not the payments made toward the original.
    @Test func duplicatingAPurchaseCopiesItsTotalButNotItsPayments() throws {
        let recurring = try RecurringTransaction.create(laptop(total: 120_000), today: today, in: context)
        try attachPayment(30_000, dated: day(2026, 9, 1), to: recurring)

        let copy = RecurringDraft(duplicating: recurring, on: today)
        #expect(copy.total?.cents == 120_000)
        #expect(copy.kind == .purchase)

        let duplicate = try RecurringTransaction.create(copy, today: today, in: context)
        #expect(duplicate.totalCents == 120_000)
        #expect(duplicate.purchaseProgress?.paid.cents == 0)
    }
}
