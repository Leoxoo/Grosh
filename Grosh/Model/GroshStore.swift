import Foundation
import SwiftData

/// The app's SwiftData store. Local only: no iCloud sync until ADR-0001's switch is flipped.
enum GroshStore {
    static let schema = Schema([
        Wallet.self,
        Category.self,
        Card.self,
        Transaction.self,
        TransactionLink.self,
    ])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
