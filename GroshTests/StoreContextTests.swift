import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A change to something the store no longer holds is refused out loud, never dropped without a word.
@MainActor
@Suite(.namedInTheLog)
struct StoreContextTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today

    init() throws {
        container = try StoreOpening.open(inMemory: true)
    }

    @Test func aWalletRemovedForGoodCantBeArchived() throws {
        let wallet = context.addWallet("Checking")
        try context.save()
        context.delete(wallet)
        try context.save()

        #expect(throws: StoreError.notInStore) { try wallet.archive(today: today) }
    }

    @Test func aWalletNeverAddedCantBeUnarchived() throws {
        let wallet = Wallet(name: "Checking")

        #expect(throws: StoreError.notInStore) { try wallet.unarchive(today: today) }
    }

    @Test func aWalletInTheStoreSavesAsBefore() throws {
        let wallet = context.addWallet("Checking")

        try wallet.archive(today: today)

        #expect(wallet.isArchived)
        #expect(!context.hasChanges)
    }
}
