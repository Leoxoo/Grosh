import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A Recurring transaction's Kind: a new one takes its category's default and keeps it when that default changes, and
/// the Recurring tab groups the schedules by it.
@MainActor
struct RecurringKindTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    /// A monthly membership from the 12th, paid from the fixture's wallet in `category`, starting as that category's
    /// default Kind, as the new-Recurring form pre-fills it.
    private func membership(in category: Category) -> RecurringDraft {
        var draft = RecurringDraft(startDay: CalendarDay(year: 2026, month: 10, day: 12))
        draft.name = "Gym"
        draft.amount = Money(cents: 2000)
        draft.wallet = store.wallet
        draft.category = category
        draft.kind = category.defaultKind
        return draft
    }

    private func recurring(named name: String, kind: RecurringKind) -> RecurringTransaction {
        let item = RecurringTransaction()
        item.name = name
        item.kind = kind
        context.insert(item)
        return item
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

    @Test func theTabGroupsSchedulesByKindInItsOrderAndLeavesOutEmptyKinds() {
        let workout = recurring(named: "Gym", kind: .regular)
        let couch = recurring(named: "Sofa", kind: .purchase)
        let streaming = recurring(named: "Netflix", kind: .subscription)
        let rent = recurring(named: "Rent", kind: .bill)
        let groups = RecurringListing.groups(of: [workout, couch, streaming, rent])
        #expect(groups.map(\.kind) == [.bill, .subscription, .purchase, .regular])
        #expect(groups.map { $0.items.count } == [1, 1, 1, 1])
        #expect(RecurringListing.groups(of: [workout]).map(\.kind) == [.regular])
        #expect(RecurringListing.groups(of: []).isEmpty)
    }

    @Test func aGroupKeepsItsSchedulesInTheOrderGiven() {
        let first = recurring(named: "Gym", kind: .regular)
        let second = recurring(named: "Books", kind: .regular)
        #expect(RecurringListing.groups(of: [first, second]).first?.items.map(\.name) == ["Gym", "Books"])
    }
}
