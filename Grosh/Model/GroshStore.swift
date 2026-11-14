import Foundation
import SwiftData

/// Builds the app's SwiftData container. Local only for now; the models already follow CloudKit's rules
/// (ADR-0001) so sync can be switched on later without a migration.
enum GroshStore {
    static let schema = Schema(synced + localOnly)

    /// The user's data: what sync, once it is switched on, carries between their devices (ADR-0001).
    static let synced: [any PersistentModel.Type] = [
        Wallet.self, Category.self, Card.self, Transaction.self, Reimbursement.self, RecurringTransaction.self,
        Person.self, ExpectedReimbursement.self,
    ]

    /// What each device works out for itself from the synced models and must never sync: the saved month totals, their
    /// dirty marks and their format (ADR-0013). Each device counts them again from its own transactions; synced, two
    /// devices' counts and marks would overwrite each other. Whoever switches CloudKit on keeps these in a
    /// configuration of their own with `cloudKitDatabase: .none`, beside the synced one.
    static let localOnly: [any PersistentModel.Type] = [
        WalletMonthTotal.self, DirtyWalletMonth.self, WalletMonthTotalFormat.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            // A new install may have no Application Support folder yet. Core Data cannot create the store without
            // one, and logs the failure, so the folder is made first.
            _ = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
        }
        return try makeContainer(
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        )
    }

    /// A container for the store file at `url` instead of the app's own, such as the 16k store the benchmarks use.
    static func makeContainer(at url: URL) throws -> ModelContainer {
        try makeContainer(ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: configuration)
    }
}
