import SwiftData

/// Builds the app's SwiftData container. Local only for now; the models already follow CloudKit's rules
/// (ADR-0001) so sync can be switched on later without a migration.
enum GroshStore {
    static let schema = Schema([Wallet.self, Category.self, Card.self, Transaction.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// The store as the app opens it: ``makeContainer(inMemory:)`` with the default categories seeded into an empty
    /// one (``CategorySeeder``). Previews open theirs in memory, so they start where a fresh install does, with the
    /// locked categories the app depends on.
    static func makeSeededContainer(inMemory: Bool = false) throws -> ModelContainer {
        let container = try makeContainer(inMemory: inMemory)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        return container
    }
}
