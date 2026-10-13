import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Grosh

/// A Card image shrunk for the Card picker: a copy exactly as many pixels as the small card it is drawn as, so it needs
/// no resizing and stays sharp on the screen it is made for.
@MainActor
struct CardImageShrinkingTests {
    private let container: ModelContainer

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    private func solidPhoto(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// A Card with an image saved as the Card editor saves one: a photo cropped to a credit card, 960 by 605 pixels.
    private func cardWithImage() throws -> Card {
        let wide = CGSize(width: 1000, height: 400)
        let photo = try solidPhoto(width: Int(wide.width), height: Int(wide.height))
        let card = Card(name: "Apple Card", kind: .credit, payingWallet: nil)
        card.imageData = try #require(
            CroppedPhoto.jpegData(cropping: photo, to: .centered(on: wide, shape: .creditCard))
        )
        container.mainContext.insert(card)
        return card
    }

    @Test func aCardImageShrunkTo16PointsIsExactlyThatTallOn2xAnd3xScreens() throws {
        let card = try cardWithImage()

        // 16 points on a 3x screen are 48 pixels; a 960 by 605 image that tall is 76 pixels wide.
        let threeX = try #require(card.shrunkImage(height: 16, scale: 3))
        #expect(threeX.height == 48)
        #expect(threeX.width == 76)

        // On a 2x screen 16 points are 32 pixels, and the image 51 pixels wide.
        let twoX = try #require(card.shrunkImage(height: 16, scale: 2))
        #expect(twoX.height == 32)
        #expect(twoX.width == 51)
    }

    @Test func theShrunkCopyKeepsTheImagesOwnProportions() throws {
        // A 1000 by 400 image is 2.5 times as wide as it is tall, so 48 pixels tall it is 120 wide, not card-shaped.
        let photo = try solidPhoto(width: 1000, height: 400)
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, photo, nil)
        #expect(CGImageDestinationFinalize(destination))

        let shrunk = try #require(CroppedPhoto.thumbnail(of: output as Data, height: 16, scale: 3))
        #expect(shrunk.height == 48)
        #expect(shrunk.width == 120)
    }

    @Test func aCardWithNoImageHasNoShrunkImage() {
        let card = Card(name: "Chase", kind: .credit, payingWallet: nil)
        container.mainContext.insert(card)

        #expect(card.shrunkImage(height: 16, scale: 3) == nil)
    }
}
