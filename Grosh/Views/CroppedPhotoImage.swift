import CoreGraphics
import SwiftUI

/// A cropped photo drawn in its shape, `height` points tall. It stands in for a symbol, so it is hidden from
/// accessibility as the symbol is: the row's name says what it is.
struct CroppedPhotoImage: View {
    let image: CGImage
    var shape: CropShape = .appIcon
    var height: CGFloat = 32
    var sizing: Sizing = .resized

    /// How the image is made `height` points tall.
    enum Sizing {
        /// Resized to fit, from an image of any size.
        case resized
        /// Already shrunk to `height` points tall on a screen of `scale` pixels per point, and drawn at its own size,
        /// never resized: a picker's label and menu rows ignore a frame, so there a resizable image is drawn at its
        /// full size.
        case shrunk(scale: CGFloat)
    }

    var body: some View {
        sized
            .clipShape(RoundedRectangle(cornerRadius: height * shape.cornerRatio, style: .continuous))
            .accessibilityHidden(true)
    }

    /// The image `height` points tall, before it is clipped to its shape.
    @ViewBuilder
    private var sized: some View {
        switch sizing {
        case .resized:
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: height * shape.aspect, height: height)
        case .shrunk(scale: let scale):
            Image(decorative: image, scale: scale)
        }
    }
}
