import CoreGraphics
import PhotosUI
import SwiftUI

extension CropShape {
    /// The label of the field that picks the photo.
    var title: String {
        switch self {
        case .appIcon: String(localized: Strings.Common.icon)
        case .creditCard: String(localized: Strings.Photos.image)
        }
    }

    /// The crop screen's title.
    var cropTitle: String {
        switch self {
        case .appIcon: String(localized: Strings.Photos.cropIcon)
        case .creditCard: String(localized: Strings.Photos.cropImage)
        }
    }
}

/// An optional cropped photo, as a form row: the current one, and buttons to choose a photo or remove it. A chosen photo
/// opens ``PhotoCropView``, and the photo is kept only once it is saved there.
struct PhotoField: View {
    let shape: CropShape
    @Binding var data: Data?

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedPhoto: PickedPhoto?
    @State private var errorMessage: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                // The picker's label is a Sendable closure, so it reads a copy rather than the main-actor binding.
                let hasPhoto = data != nil
                if let data, let image = CroppedPhoto.image(from: data) {
                    CroppedPhotoImage(image: image, shape: shape, height: 32)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(hasPhoto ? Strings.Photos.replace : Strings.Photos.choosePhoto)
                }
                if data != nil {
                    Button(Strings.Common.remove, role: .destructive) {
                        data = nil
                    }
                }
            }
            .buttonStyle(.borderless)
        } label: {
            Text(shape.title)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .sheet(item: $pickedPhoto) { picked in
            PhotoCropView(photo: picked.image, shape: shape) { cropped in
                data = cropped
            }
        }
        .errorAlert(Strings.Photos.couldntUse, message: $errorMessage)
    }

    /// Reads the chosen photo and opens the crop screen with it.
    private func load(_ item: PhotosPickerItem) async {
        pickerItem = nil
        do {
            guard let photoData = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = CroppedPhoto.decode(photoData) else {
                errorMessage = String(localized: Strings.Photos.unreadable)
                return
            }
            pickedPhoto = PickedPhoto(image: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A decoded photo waiting in the crop screen.
private struct PickedPhoto: Identifiable {
    let id = UUID()
    let image: CGImage
}
