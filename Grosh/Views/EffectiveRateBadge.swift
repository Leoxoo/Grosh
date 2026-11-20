import SwiftUI

/// An Effective rate as a green Liquid Glass capsule, the same on a Card's page and in the Card picker.
struct EffectiveRateBadge: View {
    let rate: String

    var body: some View {
        Text(rate)
            .monospacedDigit()
            .fontWeight(.semibold)
            .foregroundStyle(.onBrand)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(.brand), in: Capsule())
    }
}
