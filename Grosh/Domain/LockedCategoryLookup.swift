import Foundation
import SwiftData

/// Thrown when a locked category the app depends on isn't in the store (it is seeded on first launch and can't be deleted).
nonisolated struct MissingLockedCategory: Error, Equatable {
    let role: LockedRole
}

extension ModelContext {
    /// The locked category that plays `role`, such as Starting balance or Outgoing transfer.
    func lockedCategory(_ role: LockedRole) throws -> Category {
        let raw: String? = role.rawValue
        var descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.lockedRoleRaw == raw })
        descriptor.fetchLimit = 1
        guard let category = try fetch(descriptor).first else { throw MissingLockedCategory(role: role) }
        return category
    }
}
