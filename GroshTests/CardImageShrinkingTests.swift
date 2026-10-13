import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A Card image shrunk for the Card picker: a copy exactly as many pixels as the small card it is drawn as, so it needs
/// no resizing and stays sharp on the screen it is made for.
@MainActor
struct CardImageShrinkingTests {
    private let container: ModelContainer

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
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

    @Test func aCardWithNoImageHasNoShrunkImage() {
        let card = Card(name: "Chase", kind: .credit, payingWallet: nil)
        container.mainContext.insert(card)

        #expect(card.shrunkImage(height: 16, scale: 3) == nil)
    }
}
