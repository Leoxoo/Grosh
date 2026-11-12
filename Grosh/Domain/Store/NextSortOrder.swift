import Foundation
import SwiftData

nonisolated extension ModelContext {
    /// The position after every model of its kind already in the store, archived ones included: where something
    /// the user orders by hand (a wallet, a Card) goes when it is added.
    func nextSortOrder<Model: PersistentModel>(_ sortOrder: KeyPath<Model, Int> & Sendable) throws -> Int {
        var descriptor = FetchDescriptor<Model>(sortBy: [SortDescriptor(sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first.map { $0[keyPath: sortOrder] + 1 } ?? 0
    }
}

nonisolated extension Array {
    /// The elements in the order a list's drag leaves them: those at `source` moved to `destination`, the offsets the
    /// list reports. What a wallet's or category's new `sortOrder` numbers follow.
    func reordered(fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let moving = source.map { self[$0] }
        var reordered = enumerated().filter { !source.contains($0.offset) }.map(\.element)
        reordered.insert(contentsOf: moving, at: destination - source.count(in: 0..<destination))
        return reordered
    }
}
