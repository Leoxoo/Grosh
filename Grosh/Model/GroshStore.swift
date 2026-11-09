import Foundation
import SwiftData

/// Builds the app's SwiftData container. Local only for now; the models already follow CloudKit's rules
/// (ADR-0001) so sync can be switched on later without a migration.
enum GroshStore {
    static let schema = Schema([
        Wallet.self, Category.self, Card.self, Transaction.self, Reimbursement.self, RecurringTransaction.self,
        Person.self, ExpectedReimbursement.self,
    ])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            // A new install may have no Application Support folder yet. Core Data cannot create the store without
            // one, and logs the failure, so the folder is made first.
            _ = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
        }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

}
