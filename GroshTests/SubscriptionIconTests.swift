import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Grosh

/// A Subscription's icon: which part of a picked photo the window shows, the JPEG the crop is saved as, and when the
/// icon shows on its Recurring transaction.
@MainActor
struct SubscriptionIconTests {
    private let wide = CGSize(width: 1000, height: 400)
    private let tall = CGSize(width: 400, height: 1000)

    private func solidPhoto(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func pngData(of photo: CGImage) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, photo, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func theWholeShortSideOfAWidePhotoIsCroppedToASquareInTheMiddle() {
        #expect(IconCrop.centered(on: wide).sourceRect(in: wide) == CGRect(x: 300, y: 0, width: 400, height: 400))
    }

    @Test func aTallPhotoIsCroppedToItsWidthAndCenteredTopToBottom() {
        #expect(IconCrop.centered(on: tall).sourceRect(in: tall) == CGRect(x: 0, y: 300, width: 400, height: 400))
    }

    @Test func zoomingInShowsASmallerSquareAroundTheSameCenter() {
        let crop = IconCrop(zoom: 2, center: CGPoint(x: 500, y: 200))
        #expect(crop.sourceRect(in: wide) == CGRect(x: 400, y: 100, width: 200, height: 200))
    }

    @Test func zoomStaysInItsRangeAndTheWindowStaysOnThePhoto() {
        let center = CGPoint(x: 500, y: 200)
        #expect(IconCrop(zoom: 0.5, center: center).clamped(to: wide).zoom == IconCrop.zoomRange.lowerBound)
        #expect(IconCrop(zoom: 9, center: center).clamped(to: wide).zoom == IconCrop.zoomRange.upperBound)
        // At zoom 1 the window is 400 pixels across, so a center on the left edge is pulled in to half of that.
        #expect(IconCrop(zoom: 1, center: CGPoint(x: 0, y: 200)).clamped(to: wide).center.x == 200)
    }

    @Test func aDragNeverMovesTheWindowPastAnEdgeOfThePhoto() {
        let left = IconCrop.centered(on: wide)
            .panned(by: CGSize(width: 10_000, height: 0), windowSide: 400, in: wide)
        #expect(left.sourceRect(in: wide).minX == 0)

        let right = IconCrop.centered(on: wide)
            .panned(by: CGSize(width: -10_000, height: 0), windowSide: 400, in: wide)
        #expect(right.sourceRect(in: wide).maxX == wide.width)
    }

    @Test func aDragMovesThePhotoWithTheFingerAtTheZoomedScale() {
        // At zoom 2 the window shows 200 pixels across 400 points, so a 100-point drag moves the window 50 pixels.
        let crop = IconCrop(zoom: 2, center: CGPoint(x: 500, y: 200))
            .panned(by: CGSize(width: 100, height: 0), windowSide: 400, in: wide)
        #expect(crop.sourceRect(in: wide).origin == CGPoint(x: 350, y: 100))
    }

    @Test func theSavedIconIsASquareOfTheStoredSizeThatDecodesBack() throws {
        let photo = try solidPhoto(width: 1000, height: 400)
        let data = try #require(SubscriptionIcon.jpegData(cropping: photo, to: .centered(on: wide)))
        let icon = try #require(SubscriptionIcon.image(from: data))
        #expect(icon.width == SubscriptionIcon.pixelSide)
        #expect(icon.height == SubscriptionIcon.pixelSide)
    }

    @Test func aPickedPhotoIsDecodedNoLargerThanTheLimit() throws {
        let png = try pngData(of: try solidPhoto(width: 1000, height: 400))
        let decoded = try #require(SubscriptionIcon.decode(png, maxPixelSide: 500))
        #expect(max(decoded.width, decoded.height) == 500)
    }

    @Test func dataThatIsNotAPhotoDoesNotDecode() {
        #expect(SubscriptionIcon.decode(Data("not a photo".utf8)) == nil)
        #expect(SubscriptionIcon.image(from: Data("not a photo".utf8)) == nil)
    }

    @Test func aSubscriptionShowsItsIconAndAnotherKindShowsNone() {
        let item = RecurringTransaction()
        item.iconData = Data([1, 2, 3])
        item.kind = .subscription
        #expect(item.subscriptionIcon == Data([1, 2, 3]))

        item.kind = .bill
        #expect(item.subscriptionIcon == nil)
        // The icon waits while the Kind is something else, so changing the Kind back brings it back.
        item.kind = .subscription
        #expect(item.subscriptionIcon == Data([1, 2, 3]))
    }

    @Test func theIconIsSavedWithTheRecurringTransactionAndReplacedOrRemovedByEdits() throws {
        let store = try CategoryFixture()
        let today = CalendarDay(year: 2026, month: 10, day: 9)
        var draft = RecurringDraft(startDay: CalendarDay(year: 2026, month: 10, day: 12))
        draft.name = "Streaming"
        draft.amount = Money(cents: 1599)
        draft.wallet = store.wallet
        draft.category = try store.category("Entertainment")
        draft.kind = .subscription
        draft.iconData = Data([1, 2, 3])
        let item = try RecurringTransaction.create(draft, today: today, in: store.context)
        #expect(item.subscriptionIcon == Data([1, 2, 3]))

        var edited = RecurringDraft(editing: item)
        #expect(edited.iconData == Data([1, 2, 3]))
        edited.iconData = Data([4, 5])
        try item.update(with: edited, today: today)
        #expect(item.subscriptionIcon == Data([4, 5]))

        edited.iconData = nil
        try item.update(with: edited, today: today)
        #expect(item.subscriptionIcon == nil)
    }
}
