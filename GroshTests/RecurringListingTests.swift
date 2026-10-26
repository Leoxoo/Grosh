import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Recurring tab's wallet filter: every wallet's schedules, or only those paid from the chosen wallet, still grouped
/// by Kind. The filter changes only which schedules are listed.
@MainActor
@Suite(.namedInTheLog)
struct RecurringListingTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }

    init() throws {
        store = try CategoryFixture()
    }

    private func schedule(named name: String, in wallet: Wallet?, kind: RecurringKind = .regular) -> RecurringTransaction {
        let item = RecurringTransaction()
        item.name = name
        item.wallet = wallet
        item.kind = kind
        context.insert(item)
        return item
    }

    private func wallet(named name: String) -> Wallet {
        let added = Wallet(name: name)
        context.insert(added)
        return added
    }

    @Test func noWalletChosenListsEveryWalletsSchedules() {
        let savings = wallet(named: "Savings")
        let rent = schedule(named: "Rent", in: store.wallet, kind: .bill)
        let gym = schedule(named: "Gym", in: savings)
        let phone = schedule(named: "Phone", in: nil, kind: .subscription)
        let groups = RecurringListing.groups(of: [rent, gym, phone])
        #expect(groups.map(\.kind) == [.bill, .subscription, .regular])
        #expect(groups.flatMap { $0.items }.count == 3)
    }

    @Test func aChosenWalletListsOnlyItsOwnSchedulesInTheirOrder() {
        let savings = wallet(named: "Savings")
        let rent = schedule(named: "Rent", in: store.wallet, kind: .bill)
        let gym = schedule(named: "Gym", in: savings)
        let phone = schedule(named: "Phone", in: store.wallet, kind: .subscription)
        let groups = RecurringListing.groups(of: [rent, gym, phone], wallet: store.wallet)
        #expect(groups.map(\.kind) == [.bill, .subscription])
        #expect(groups.flatMap { $0.items }.map(\.name) == ["Rent", "Phone"])
    }

    @Test func sectionsWithNoMatchesAreHiddenUnderAWalletFilter() {
        let savings = wallet(named: "Savings")
        let rent = schedule(named: "Rent", in: store.wallet, kind: .bill)
        let gym = schedule(named: "Gym", in: savings)
        let groups = RecurringListing.groups(of: [rent, gym], wallet: savings)
        #expect(groups.map(\.kind) == [.regular])
        #expect(groups.flatMap { $0.items }.map(\.name) == ["Gym"])
    }

    @Test func aWalletWithNoSchedulesListsNothing() {
        let cash = wallet(named: "Cash")
        let rent = schedule(named: "Rent", in: store.wallet, kind: .bill)
        #expect(RecurringListing.groups(of: [rent], wallet: cash).isEmpty)
    }
}
