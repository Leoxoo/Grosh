import CoreGraphics
import SwiftUI

/// A Card's mark, `height` points tall: its image in a credit card's proportions when it has one, or else the view
/// `symbol` draws. Each list draws its symbol at its own size and style, so only the choice between the two is shared.
struct CardMark<Symbol: View>: View {
    let image: CGImage?
    let height: CGFloat
    @ViewBuilder let symbol: () -> Symbol

    var body: some View {
        if let image {
            CroppedPhotoImage(image: image, shape: .creditCard, height: height)
        } else {
            symbol()
        }
    }
}
