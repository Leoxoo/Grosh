import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// A photo of one solid blue, `width` by `height` pixels, for tests. The blue averages to the palette's blue.
nonisolated func solidPhoto(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

/// `photo` as PNG data, as a picked photo arrives, for tests.
nonisolated func pngData(of photo: CGImage) throws -> Data {
    let output = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, photo, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}
