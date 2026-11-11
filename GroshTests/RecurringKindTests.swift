import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A Recurring transaction's Kind: a new one takes its category's default and keeps it when that default changes. How
/// the Recurring tab groups the schedules by it is in `RecurringListingTests`.
@MainActor
@Suite(.namedInTheLog)
struct RecurringKindTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
    }

    /// A monthly membership from the 12th, paid from the fixture's wallet in `category`, starting as that category's
    /// default Kind, as the new-Recurring form pre-fills it.
    private func membership(in category: Grosh.Category) -> RecurringDraft {
        var draft = RecurringDraft(startDay: CalendarDay(year: 2026, month: 10, day: 12))
        draft.name = "Gym"
        draft.amount = Money(cents: 2000)
        draft.wallet = store.checking
        draft.category = category
        draft.kind = category.defaultKind
        return draft
    }

    @Test func aRecurringTransactionIsRegularUnlessItsKindIsSet() {
        #expect(RecurringTransaction().kind == .regular)
    }

    @Test func aNewOneStartsWithItsCategoryDefaultKindAndKeepsItWhenTheDefaultChanges() throws {
        let shopping = try store.category("Shopping")
        shopping.ownKind = .purchase
        let made = try RecurringTransaction.create(membership(in: shopping), today: today, in: context)
        #expect(made.kind == .purchase)
        shopping.ownKind = .bill
        #expect(made.kind == .purchase)
    }

    @Test func editingKeepsTheKindUnlessTheUserChangesIt() throws {
        let shopping = try store.category("Shopping")
        shopping.ownKind = .purchase
        let made = try RecurringTransaction.create(membership(in: shopping), today: today, in: context)
        var edited = RecurringDraft(editing: made)
        #expect(edited.kind == .purchase)
        edited.kind = .subscription
        try made.update(with: edited, today: today)
        #expect(made.kind == .subscription)
    }
}
