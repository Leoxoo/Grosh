import CoreGraphics
import SwiftUI

/// A Card's mark, `height` points tall in a credit card's proportions: its image when it has one, or else its symbol in
/// the Card's color, drawn to fill the same slot. The image and the symbol take the same room, so names beside them line
/// up whichever a Card has and no list sizes the two apart.
struct CardMark: View {
    let image: CGImage?
    let color: Color
    let height: CGFloat
    /// How the image is made `height` points tall: resized, unless it is a copy already shrunk to that size.
    var sizing: CroppedPhotoImage.Sizing = .resized

    var body: some View {
        switch sizing {
        case .resized:
            mark
                .frame(width: height * CropShape.creditCard.aspect, height: height)
        case .shrunk:
            // A picker's label and menu rows ignore a frame and a resizable image, so the symbol keeps the surrounding
            // font there.
            mark
        }
    }

    @ViewBuilder private var mark: some View {
        if let image {
            CroppedPhotoImage(image: image, shape: .creditCard, height: height, sizing: sizing)
        } else if case .resized = sizing {
            CardSymbol(color: color)
        } else {
            Image(systemName: Card.symbolName)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
    }
}

extension CardMark {
    /// `card`'s mark. Given the screen's `shrunkForScale`, the image is a copy shrunk to `height` and drawn at its own
    /// size, for a picker or menu, which ignores a frame.
    init(card: Card, height: CGFloat, shrunkForScale scale: CGFloat? = nil) {
        if let scale {
            self.init(
                image: card.shrunkImage(height: height, scale: scale), color: card.color.color, height: height,
                sizing: .shrunk(scale: scale)
            )
        } else {
            self.init(image: card.image, color: card.color.color, height: height)
        }
    }
}

/// A Card's symbol in its color, filling the room a Card's image takes.
struct CardSymbol: View {
    let color: Color

    var body: some View {
        Image(systemName: Card.symbolName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
