import CoreGraphics
import SwiftUI

/// A Card's mark, `height` points tall: its image in a credit card's proportions when it has one, or else the view
/// `symbol` draws. Each list draws its symbol at its own size and style, so only the choice between the two is shared.
struct CardMark<Symbol: View>: View {
    let image: CGImage?
    let height: CGFloat
    /// How the image is made `height` points tall: resized, unless it is a copy already shrunk to that size.
    var sizing: CroppedPhotoImage.Sizing = .resized
    @ViewBuilder let symbol: () -> Symbol

    var body: some View {
        if let image {
            CroppedPhotoImage(image: image, shape: .creditCard, height: height, sizing: sizing)
        } else {
            symbol()
        }
    }
}

extension CardMark where Symbol == CardSymbol {
    /// `card`'s mark beside a transaction or in a picker: its image, or its symbol in the Card's color in `symbolFont`
    /// (the surrounding font when `nil`). Given the screen's `shrunkForScale`, the image is a copy shrunk to `height`
    /// and drawn at its own size, for a picker or menu, which ignores a frame.
    init(card: Card, height: CGFloat, symbolFont: Font? = nil, shrunkForScale scale: CGFloat? = nil) {
        if let scale {
            self.init(
                image: card.shrunkImage(height: height, scale: scale), height: height, sizing: .shrunk(scale: scale)
            ) {
                CardSymbol(color: card.color.color, font: symbolFont)
            }
        } else {
            self.init(image: card.image, height: height) {
                CardSymbol(color: card.color.color, font: symbolFont)
            }
        }
    }
}

/// A Card's symbol in its color, drawn when the Card has no image.
struct CardSymbol: View {
    let color: Color
    let font: Font?

    var body: some View {
        Image(systemName: Card.symbolName)
            .font(font)
            .foregroundStyle(color)
    }
}
