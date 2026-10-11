import CoreGraphics
import SwiftUI

/// A Subscription's cropped icon, drawn in the shape of an app icon. It stands in for a category's symbol, so it is
/// hidden from accessibility as the symbol is: the row's name says what it is.
struct SubscriptionIconImage: View {
    let image: CGImage
    var size: CGFloat = 32

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * SubscriptionIcon.cornerRatio, style: .continuous))
            .accessibilityHidden(true)
    }
}
