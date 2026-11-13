import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Recurring tab's list: the schedules grouped by Kind in the tab's order, and its wallet filter, which changes only
/// which schedules are listed.
@MainActor
@Suite(.namedInTheLog)
struct RecurringListingTests {
    private let store: TestStore
    private var context: ModelContext { store.context }

    init() throws {
        store = try TestStore()
    }

    private func schedule(named name: String, in wallet: Wallet?, kind: RecurringKind = .regular) -> RecurringTransaction {
        let item = RecurringTransaction()
        item.name = name
        item.wallet = wallet
        item.kind = kind
        context.insert(item)
        return item
    }

    @Test func noWalletChosenListsEveryWalletsSchedules() {
        let savings = context.addWallet("Savings")
        let rent = schedule(named: "Rent", in: store.checking, kind: .bill)
        let gym = schedule(named: "Gym", in: savings)
        let phone = schedule(named: "Phone", in: nil, kind: .subscription)
        let groups = RecurringListing.groups(of: [rent, gym, phone])
        #expect(groups.map(\.kind) == [.bill, .subscription, .regular])
        #expect(groups.flatMap { $0.items }.count == 3)
    }

    @Test func aChosenWalletListsOnlyItsOwnSchedulesInTheirOrder() {
        let savings = context.addWallet("Savings")
        let rent = schedule(named: "Rent", in: store.checking, kind: .bill)
        let gym = schedule(named: "Gym", in: savings)
        let phone = schedule(named: "Phone", in: store.checking, kind: .subscription)
        let groups = RecurringListing.groups(of: [rent, gym, phone], wallet: store.checking)
        #expect(groups.map(\.kind) == [.bill, .subscription])
        #expect(groups.flatMap { $0.items }.map(\.name) == ["Rent", "Phone"])
    }

    @Test func sectionsWithNoMatchesAreHiddenUnderAWalletFilter() {
        let savings = context.addWallet("Savings")
        let rent = schedule(named: "Rent", in: store.checking, kind: .bill)
        let gym = schedule(named: "Gym", in: savings)
        let groups = RecurringListing.groups(of: [rent, gym], wallet: savings)
        #expect(groups.map(\.kind) == [.regular])
        #expect(groups.flatMap { $0.items }.map(\.name) == ["Gym"])
    }

    @Test func aWalletWithNoSchedulesListsNothing() {
        let cash = context.addWallet("Cash")
        let rent = schedule(named: "Rent", in: store.checking, kind: .bill)
        #expect(RecurringListing.groups(of: [rent], wallet: cash).isEmpty)
    }

    @Test func theTabGroupsSchedulesByKindInItsOrderAndLeavesOutEmptyKinds() {
        let workout = schedule(named: "Gym", in: nil)
        let couch = schedule(named: "Sofa", in: nil, kind: .purchase)
        let streaming = schedule(named: "Netflix", in: nil, kind: .subscription)
        let rent = schedule(named: "Rent", in: nil, kind: .bill)
        let groups = RecurringListing.groups(of: [workout, couch, streaming, rent])
        #expect(groups.map(\.kind) == [.bill, .subscription, .purchase, .regular])
        #expect(groups.map { $0.items.count } == [1, 1, 1, 1])
        #expect(RecurringListing.groups(of: [workout]).map(\.kind) == [.regular])
        #expect(RecurringListing.groups(of: []).isEmpty)
    }

    @Test func aGroupKeepsItsSchedulesInTheOrderGiven() {
        let first = schedule(named: "Gym", in: nil)
        let second = schedule(named: "Books", in: nil)
        #expect(RecurringListing.groups(of: [first, second]).first?.items.map(\.name) == ["Gym", "Books"])
    }
}
