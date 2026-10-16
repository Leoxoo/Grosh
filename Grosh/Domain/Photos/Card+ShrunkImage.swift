import CoreGraphics
import Foundation

extension Card {
    /// The Card image as a small card `height` points tall on a screen of `scale` pixels per point: a shrunk copy that
    /// keeps the image's proportions and is drawn at its own size, so no picker or menu can stretch it. `nil` when the
    /// Card has no image.
    func shrunkImage(height: CGFloat, scale: CGFloat) -> CGImage? {
        imageData.flatMap { CroppedPhoto.shrunkImage(from: $0, height: height, scale: scale) }
    }
}
