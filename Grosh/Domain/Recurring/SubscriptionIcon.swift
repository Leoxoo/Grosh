import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A Subscription's icon: a square cropped from a photo or screenshot, kept as JPEG data and drawn in an app-icon shape.
nonisolated enum SubscriptionIcon {
    /// The stored icon's side in pixels, more than any row draws it at on any screen.
    static let pixelSide = 256
    /// The app-icon corner radius, as a share of the icon's side.
    static let cornerRatio: CGFloat = 0.225

    /// A photo decoded upright and no larger than `maxPixelSide` on its long side, so cropping works on a bounded image
    /// however large the photo is. `nil` if the data isn't an image.
    static func decode(_ data: Data, maxPixelSide: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image a stored icon holds, or `nil` if the data isn't an image.
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The square `crop` shows of `photo`, as JPEG data `pixelSide` pixels across. `nil` if it can't be drawn.
    static func jpegData(cropping photo: CGImage, to crop: IconCrop) -> Data? {
        let photoSize = CGSize(width: photo.width, height: photo.height)
        guard let region = photo.cropping(to: crop.sourceRect(in: photoSize).integral) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixelSide,
            height: pixelSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let square = CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        // White under any transparent part of the photo, so it never shows as black.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(square)
        context.interpolationQuality = .high
        context.draw(region, in: square)
        guard let icon = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, icon, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
