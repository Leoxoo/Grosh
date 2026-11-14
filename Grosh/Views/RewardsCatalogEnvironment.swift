import SwiftUI

extension EnvironmentValues {
    /// The rewards catalog screens read Cards' rates from: the one the app ships, unless a preview gives another.
    @Entry var rewardsCatalog: RewardsCatalog = .shipped
}
