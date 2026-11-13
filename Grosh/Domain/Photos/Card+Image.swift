import CoreGraphics
import Foundation

extension Card {
    /// The Card's image, decoded for drawing, or `nil` when it has none. Decoded once for every row that shows it.
    var image: CGImage? {
        imageData.flatMap(CroppedPhoto.image(from:))
    }

    /// The Card image as a small card `height` points tall on a screen of `scale` pixels per point: a shrunk copy that
    /// keeps the image's proportions and is drawn at its own size, so no picker or menu can stretch it. Shrunk once for
    /// every row that shows it at that size. `nil` when the Card has no image.
    func shrunkImage(height: CGFloat, scale: CGFloat) -> CGImage? {
        imageData.flatMap { CroppedPhoto.shrunkImage(from: $0, height: height, scale: scale) }
    }
}
