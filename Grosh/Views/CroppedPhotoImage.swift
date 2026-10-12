import CoreGraphics
import SwiftUI

/// A cropped photo drawn in its shape, `height` points tall. It stands in for a symbol, so it is hidden from
/// accessibility as the symbol is: the row's name says what it is.
struct CroppedPhotoImage: View {
    let image: CGImage
    var shape: CropShape = .appIcon
    var height: CGFloat = 32

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: height * shape.aspect, height: height)
            .clipShape(RoundedRectangle(cornerRadius: height * shape.cornerRatio, style: .continuous))
            .accessibilityHidden(true)
    }
}
