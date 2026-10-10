import Foundation
import SwiftData

/// Thrown when a locked category the app depends on isn't in the store (it is seeded on first launch and can't be deleted).
nonisolated struct MissingLockedCategory: Error, Equatable {
    let role: LockedRole
}

extension MissingLockedCategory: LocalizedError {
    var errorDescription: String? {
        String(localized: "Grosh can't do this without its “\(role.seededName)” category, which is missing.")
    }
}

nonisolated extension LockedRole {
    /// The name the category playing this role is seeded with (``DefaultCategories``). A locked category keeps it:
    /// only its icon can change.
    var seededName: String {
        func named(in seeds: [CategorySeed]) -> String? {
            for seed in seeds {
                if seed.lockedRole == self { return seed.name }
                if let name = named(in: seed.children) { return name }
            }
            return nil
        }
        return named(in: DefaultCategories.tree) ?? rawValue
    }
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

    /// Other Income for money coming in (`type` Income), Other Expense for money going out: what the app files an
    /// amount under until the user picks another category, such as a balance adjustment's reason, an overpayment or
    /// a forgiven amount.
    func otherCategory(_ type: CategoryType) throws -> Category {
        try lockedCategory(type == .income ? .otherIncome : .otherExpense)
    }
}
