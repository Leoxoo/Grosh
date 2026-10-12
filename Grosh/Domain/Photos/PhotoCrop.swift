import CoreGraphics

/// The shape a cropped photo is kept and drawn in: a Subscription's app icon, or a Card's image in a credit card's
/// proportions.
nonisolated enum CropShape: Sendable {
    case appIcon
    case creditCard

    /// Width over height.
    var aspect: CGFloat {
        switch self {
        case .appIcon: 1
        case .creditCard: 85.6 / 53.98 // ISO/IEC 7810 ID-1, the size of a payment card
        }
    }

    /// The corner radius as a share of the height.
    var cornerRatio: CGFloat {
        switch self {
        case .appIcon: 0.225
        case .creditCard: 0.06
        }
    }

    /// The stored image's width in pixels, more than any row or detail draws it at on any screen.
    var pixelWidth: Int {
        switch self {
        case .appIcon: 256
        case .creditCard: 960
        }
    }
}

/// Where a crop window sits on a picked photo, in the photo's pixels: how far the photo is zoomed in, which point of it
/// lies under the window's center, and the window's shape. The window always stays on the photo.
nonisolated struct PhotoCrop: Equatable, Sendable {
    /// 1 fits the window to the photo's short side; larger zooms in on the same center.
    var zoom: CGFloat
    /// The photo point under the window's center, in pixels.
    var center: CGPoint
    var shape: CropShape = .appIcon

    static let zoomRange: ClosedRange<CGFloat> = 1...5

    /// The whole photo, centered, with the largest window of `shape` that fits it.
    static func centered(on imageSize: CGSize, shape: CropShape = .appIcon) -> PhotoCrop {
        PhotoCrop(zoom: 1, center: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2), shape: shape)
    }

    /// The window's width over its height.
    var aspect: CGFloat { shape.aspect }

    /// The window's size in pixels: the largest window of its shape that fits the photo, at this zoom.
    func size(in imageSize: CGSize) -> CGSize {
        let fitWidth = min(imageSize.width, imageSize.height * aspect)
        return CGSize(width: fitWidth / zoom, height: fitWidth / aspect / zoom)
    }

    /// The part of the photo the window shows, in pixels.
    func sourceRect(in imageSize: CGSize) -> CGRect {
        let crop = clamped(to: imageSize)
        let size = crop.size(in: imageSize)
        return CGRect(
            x: crop.center.x - size.width / 2,
            y: crop.center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// This crop with its zoom in range, and its center far enough inside the photo that the window stays on it.
    func clamped(to imageSize: CGSize) -> PhotoCrop {
        var crop = self
        crop.zoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let size = crop.size(in: imageSize)
        crop.center = CGPoint(
            x: min(max(center.x, size.width / 2), imageSize.width - size.width / 2),
            y: min(max(center.y, size.height / 2), imageSize.height - size.height / 2)
        )
        return crop
    }

    /// This crop moved by a drag of `translation` points on a window `windowWidth` points across. The photo moves with
    /// the finger, so dragging right shows more of its left side.
    func panned(by translation: CGSize, windowWidth: CGFloat, in imageSize: CGSize) -> PhotoCrop {
        let pixelsPerPoint = size(in: imageSize).width / windowWidth
        var crop = self
        crop.center = CGPoint(
            x: center.x - translation.width * pixelsPerPoint,
            y: center.y - translation.height * pixelsPerPoint
        )
        return crop.clamped(to: imageSize)
    }
}
