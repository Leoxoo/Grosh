import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo cropped to a ``CropShape`` and kept as JPEG data: a Subscription's icon, or a Card's image.
nonisolated enum CroppedPhoto {
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

    /// The image a stored crop holds, or `nil` if the data isn't an image. The same data gives back the same image, so
    /// a list showing one Card image or Subscription icon on many rows decodes it once rather than for every row.
    static func image(from data: Data) -> CGImage? {
        let key = data as NSData
        if let image = decoded.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        decoded.setObject(image, forKey: key)
        return image
    }

    /// The images of the crops decoded lately, by their data. The system empties it when memory runs low.
    private nonisolated(unsafe) static let decoded = NSCache<NSData, CGImage>()

    /// The image a stored crop holds, shrunk to `height` points tall on a screen of `scale` pixels per point, its width
    /// keeping the image's proportions. Drawn at its own size it is exactly that tall and sharp, so no layout needs to
    /// resize it. `nil` if the data isn't an image.
    ///
    /// It draws the copy itself rather than through ``decode(_:maxPixelSide:)``: ImageIO bounds a thumbnail only by its
    /// long side and works out the short side with rounding it doesn't document, so it can't promise the exact pixel
    /// height a sharp mark needs.
    static func shrunkImage(from data: Data, height: CGFloat, scale: CGFloat) -> CGImage? {
        guard let stored = image(from: data), stored.width > 0, stored.height > 0 else { return nil }
        let pixelHeight = max(1, Int((height * scale).rounded()))
        let pixelWidth = max(1, Int((CGFloat(pixelHeight) * CGFloat(stored.width) / CGFloat(stored.height)).rounded()))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(stored, in: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
        return context.makeImage()
    }

    /// The part of `photo` that `crop` shows, as JPEG data `crop.shape.pixelWidth` pixels across. `nil` if it can't be
    /// drawn.
    static func jpegData(cropping photo: CGImage, to crop: PhotoCrop) -> Data? {
        let photoSize = CGSize(width: photo.width, height: photo.height)
        guard let region = photo.cropping(to: crop.sourceRect(in: photoSize).integral) else { return nil }
        let width = crop.shape.pixelWidth
        let height = Int((CGFloat(width) / crop.aspect).rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        // White under any transparent part of the photo, so it never shows as black.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(frame)
        context.interpolationQuality = .high
        context.draw(region, in: frame)
        guard let cropped = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The palette color nearest the average color of the photo `data` holds, or `nil` if the data isn't an image.
    static func averagePaletteColor(of data: Data) -> PaletteColor? {
        guard let decoded = image(from: data) else { return nil }
        let input = CIImage(cgImage: decoded)
        guard let average = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]
        )?.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return PaletteColor.nearest(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }
}

nonisolated extension PaletteColor {
    /// Each chromatic palette color's hue in degrees, as its system color has it.
    private static let hues: [(color: PaletteColor, degrees: Double)] = [
        (.red, 4), (.orange, 36), (.yellow, 48), (.green, 135), (.mint, 176), (.teal, 191), (.cyan, 200),
        (.blue, 211), (.indigo, 245), (.purple, 277), (.pink, 348),
    ]

    /// The palette color for an RGB color whose channels run from 0 to 1: gray when it is close to neutral, brown when
    /// it is a muted orange, and otherwise the color whose hue is nearest.
    static func nearest(red: Double, green: Double, blue: Double) -> PaletteColor {
        let high = max(red, green, blue)
        let chroma = high - min(red, green, blue)
        let saturation = high > 0 ? chroma / high : 0
        guard saturation >= 0.2 else { return .gray }

        let hue: Double
        if high == red {
            hue = 60 * (green - blue) / chroma
        } else if high == green {
            hue = 60 * ((blue - red) / chroma + 2)
        } else {
            hue = 60 * ((red - green) / chroma + 4)
        }
        let degrees = (hue + 360).truncatingRemainder(dividingBy: 360)
        if (15..<50).contains(degrees), saturation < 0.6 {
            return .brown
        }
        return hues.min { circularGap($0.degrees, degrees) < circularGap($1.degrees, degrees) }?.color ?? .gray
    }

    /// The distance between two hues in degrees, the short way around the color wheel.
    private static func circularGap(_ a: Double, _ b: Double) -> Double {
        let gap = abs(a - b)
        return min(gap, 360 - gap)
    }
}
