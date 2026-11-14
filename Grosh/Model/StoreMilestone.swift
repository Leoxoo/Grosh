import Foundation
import SwiftData

/// A one-time step this store has taken, such as filling in the default categories' Rewards as, so it is never taken
/// again however the user changes what it set. A store holds at most one of each name; a second one, as two synced
/// devices could make, means the same.
@Model
final class StoreMilestone {
    var name: String = ""
    var reachedAt: Date = Date.now

    init(name: String) {
        self.name = name
    }
}
