import SwiftData

extension PersistentModel {
    /// Whether the record has left the store: deleted, or detached from its context once that deletion was saved. A
    /// screen or sheet showing it may still draw once more while it closes, and reading its relationships then would
    /// fault, so it checks this first.
    var isGone: Bool { isDeleted || modelContext == nil }
}
