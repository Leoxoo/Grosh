import CoreGraphics
import Foundation
import Testing
@testable import Grosh

/// A cropped photo: which part of a picked photo the window shows, the JPEG a crop is saved as, a copy shrunk for a
/// small mark, the color a photo averages to, and when a Subscription's icon shows on its Recurring transaction.
@MainActor
@Suite(.namedInTheLog)
struct CroppedPhotoTests {
    private let wide = CGSize(width: 1000, height: 400)
    private let tall = CGSize(width: 400, height: 1000)

    @Test func theWholeShortSideOfAWidePhotoIsCroppedToASquareInTheMiddle() {
        #expect(PhotoCrop.centered(on: wide).sourceRect(in: wide) == CGRect(x: 300, y: 0, width: 400, height: 400))
    }

    @Test func aTallPhotoIsCroppedToItsWidthAndCenteredTopToBottom() {
        #expect(PhotoCrop.centered(on: tall).sourceRect(in: tall) == CGRect(x: 0, y: 300, width: 400, height: 400))
    }

    @Test func zoomingInShowsASmallerSquareAroundTheSameCenter() {
        let crop = PhotoCrop(zoom: 2, center: CGPoint(x: 500, y: 200))
        #expect(crop.sourceRect(in: wide) == CGRect(x: 400, y: 100, width: 200, height: 200))
    }

    @Test func zoomStaysInItsRangeAndTheWindowStaysOnThePhoto() {
        let center = CGPoint(x: 500, y: 200)
        #expect(PhotoCrop(zoom: 0.5, center: center).clamped(to: wide).zoom == PhotoCrop.zoomRange.lowerBound)
        #expect(PhotoCrop(zoom: 9, center: center).clamped(to: wide).zoom == PhotoCrop.zoomRange.upperBound)
        // At zoom 1 the window is 400 pixels across, so a center on the left edge is pulled in to half of that.
        #expect(PhotoCrop(zoom: 1, center: CGPoint(x: 0, y: 200)).clamped(to: wide).center.x == 200)
    }

    @Test func aDragNeverMovesTheWindowPastAnEdgeOfThePhoto() {
        let left = PhotoCrop.centered(on: wide)
            .panned(by: CGSize(width: 10_000, height: 0), windowWidth: 400, in: wide)
        #expect(left.sourceRect(in: wide).minX == 0)

        let right = PhotoCrop.centered(on: wide)
            .panned(by: CGSize(width: -10_000, height: 0), windowWidth: 400, in: wide)
        #expect(right.sourceRect(in: wide).maxX == wide.width)
    }

    @Test func aDragMovesThePhotoWithTheFingerAtTheZoomedScale() {
        // At zoom 2 the window shows 200 pixels across 400 points, so a 100-point drag moves the window 50 pixels.
        let crop = PhotoCrop(zoom: 2, center: CGPoint(x: 500, y: 200))
            .panned(by: CGSize(width: 100, height: 0), windowWidth: 400, in: wide)
        #expect(crop.sourceRect(in: wide).origin == CGPoint(x: 350, y: 100))
    }

    @Test func aCardImageWindowHasACreditCardsProportions() {
        let size = PhotoCrop.centered(on: wide, shape: .creditCard).size(in: wide)
        #expect(abs(size.width / size.height - CropShape.creditCard.aspect) < 0.001)
        #expect(size.height <= wide.height)
    }

    @Test func theSavedIconIsASquareOfTheStoredSizeThatDecodesBack() throws {
        let photo = try solidPhoto(width: 1000, height: 400)
        let data = try #require(CroppedPhoto.jpegData(cropping: photo, to: .centered(on: wide)))
        let icon = try #require(CroppedPhoto.image(from: data))
        #expect(icon.width == CropShape.appIcon.pixelWidth)
        #expect(icon.height == CropShape.appIcon.pixelWidth)
    }

    @Test func theSavedCardImageIsLandscapeAtItsStoredWidth() throws {
        let photo = try solidPhoto(width: 1000, height: 400)
        let data = try #require(CroppedPhoto.jpegData(cropping: photo, to: .centered(on: wide, shape: .creditCard)))
        let image = try #require(CroppedPhoto.image(from: data))
        #expect(image.width == CropShape.creditCard.pixelWidth)
        #expect(image.height < image.width)
    }

    @Test func aPickedPhotoIsDecodedNoLargerThanTheLimit() throws {
        let png = try pngData(of: try solidPhoto(width: 1000, height: 400))
        let decoded = try #require(CroppedPhoto.decode(png, maxPixelSide: 500))
        #expect(max(decoded.width, decoded.height) == 500)
    }

    @Test func theShrunkCopyKeepsTheImagesOwnProportions() throws {
        // A 1000 by 400 image is 2.5 times as wide as it is tall, so 48 pixels tall it is 120 wide, not card-shaped.
        let png = try pngData(of: try solidPhoto(width: 1000, height: 400))
        let shrunk = try #require(CroppedPhoto.shrunkImage(from: png, height: 16, scale: 3))
        #expect(shrunk.height == 48)
        #expect(shrunk.width == 120)
    }

    @Test func dataThatIsNotAPhotoDoesNotDecode() {
        #expect(CroppedPhoto.decode(Data("not a photo".utf8)) == nil)
        #expect(CroppedPhoto.image(from: Data("not a photo".utf8)) == nil)
    }

    @Test func aPhotoAveragesToTheNearestPaletteColor() throws {
        // The solid photo is a blue, so its average is that blue.
        let data = try pngData(of: try solidPhoto(width: 1000, height: 400))
        #expect(CroppedPhoto.averagePaletteColor(of: data) == .blue)
        #expect(CroppedPhoto.averagePaletteColor(of: Data("not a photo".utf8)) == nil)
    }

    @Test func aColorIsTheNearestPaletteEntryToItsHueOrGrayOrBrownWhenMuted() {
        #expect(PaletteColor.nearest(red: 0.2, green: 0.5, blue: 0.9) == .blue)
        #expect(PaletteColor.nearest(red: 0.635, green: 0.518, blue: 0.369) == .brown)
        #expect(PaletteColor.nearest(red: 0.5, green: 0.5, blue: 0.5) == .gray)
    }

    @Test func aCardImageSetsItsColorAndRemovingItKeepsTheColor() throws {
        let data = try pngData(of: try solidPhoto(width: 1000, height: 400))
        var draft = CardDraft(name: "Card", kind: .credit, payingWallet: nil)
        draft.color = .red

        draft.setImage(data)
        #expect(draft.imageData == data)
        #expect(draft.color == .blue)

        draft.setImage(nil)
        #expect(draft.imageData == nil)
        #expect(draft.color == .blue)
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
