import Foundation
import SwiftData

/// Opens the store the way every screen expects to find it.
enum StoreOpening {
    /// The store as the app opens it: ``GroshStore/makeContainer(inMemory:)`` brought up to date by ``prepare(_:)``.
    /// Previews open theirs in memory, so they start where a fresh install does, with the locked categories the app
    /// depends on.
    static func open(inMemory: Bool = false) throws -> ModelContainer {
        let container = try GroshStore.makeContainer(inMemory: inMemory)
        try prepare(container.mainContext)
        return container
    }

    /// Brings a store just opened up to date before any screen reads it: the default categories seeded into an empty
    /// one and any missing ones restored (``CategorySeeder``), the With names typed before there were people turned into
    /// people (``Person/migrateWithNames(in:)``, ADR-0009), so no screen ever sees a With without its Person, and every
    /// link given its kind (``Transaction/migrateLinkKinds(in:)``, ADR-0012). Each step does nothing on a store already
    /// up to date.
    static func prepare(_ context: ModelContext) throws {
        try CategorySeeder.seedIfNeeded(in: context)
        try CategorySeeder.restoreMissingDefaults(in: context)
        try Person.migrateWithNames(in: context)
        try Transaction.migrateLinkKinds(in: context)
    }
}
