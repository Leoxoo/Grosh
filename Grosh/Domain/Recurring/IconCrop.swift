import CoreGraphics

/// Where a Subscription's icon window sits on a picked photo, in the photo's pixels: how far the photo is zoomed in and
/// which point of it lies under the window's center. The window always stays on the photo.
nonisolated struct IconCrop: Equatable, Sendable {
    /// 1 fits the photo's short side to the window; larger zooms in on the same center.
    var zoom: CGFloat
    /// The photo point under the window's center, in pixels.
    var center: CGPoint

    static let zoomRange: ClosedRange<CGFloat> = 1...5

    /// The whole photo, zoomed to fit its short side, centered.
    static func centered(on imageSize: CGSize) -> IconCrop {
        IconCrop(zoom: 1, center: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2))
    }

    /// The window's side in pixels: the photo's short side at this zoom.
    func side(in imageSize: CGSize) -> CGFloat {
        min(imageSize.width, imageSize.height) / zoom
    }

    /// The square of the photo the window shows, in pixels.
    func sourceRect(in imageSize: CGSize) -> CGRect {
        let crop = clamped(to: imageSize)
        let side = crop.side(in: imageSize)
        return CGRect(x: crop.center.x - side / 2, y: crop.center.y - side / 2, width: side, height: side)
    }

    /// This crop with its zoom in range, and its center far enough inside the photo that the window stays on it.
    func clamped(to imageSize: CGSize) -> IconCrop {
        let clampedZoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let half = IconCrop(zoom: clampedZoom, center: center).side(in: imageSize) / 2
        let x = min(max(center.x, half), imageSize.width - half)
        let y = min(max(center.y, half), imageSize.height - half)
        return IconCrop(zoom: clampedZoom, center: CGPoint(x: x, y: y))
    }

    /// This crop moved by a drag of `translation` points on a window `windowSide` points across. The photo moves with
    /// the finger, so dragging right shows more of its left side.
    func panned(by translation: CGSize, windowSide: CGFloat, in imageSize: CGSize) -> IconCrop {
        let pixelsPerPoint = side(in: imageSize) / windowSide
        let moved = CGPoint(
            x: center.x - translation.width * pixelsPerPoint,
            y: center.y - translation.height * pixelsPerPoint
        )
        return IconCrop(zoom: zoom, center: moved).clamped(to: imageSize)
    }
}
