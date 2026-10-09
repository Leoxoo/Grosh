import Foundation
import SwiftData

extension ModelContext {
    /// The position after every model of its kind already in the store, archived ones included: where something
    /// the user orders by hand (a wallet, a Card) goes when it is added.
    func nextSortOrder<Model: PersistentModel>(_ sortOrder: KeyPath<Model, Int>) throws -> Int {
        var descriptor = FetchDescriptor<Model>(sortBy: [SortDescriptor(sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first.map { $0[keyPath: sortOrder] + 1 } ?? 0
    }
}
