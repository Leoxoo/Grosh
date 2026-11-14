import Foundation
import SwiftData

/// A Reward category the user added because a card earns on something the fixed list lacks, such as Pet stores. Only
/// rates the user enters earn on it. A category counts as it by holding its ``key`` (``Category/ownRewardsAs``).
@Model
final class OwnRewardCategory {
    /// What a category's Rewards as holds to count as this one. Never one of the fixed list's ids, which are words
    /// like `dining`.
    var key: String = UUID().uuidString
    var name: String = ""
    var sortOrder: Int = 0

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }
}
