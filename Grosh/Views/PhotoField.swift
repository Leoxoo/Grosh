import CoreGraphics
import PhotosUI
import SwiftUI

extension CropShape {
    /// The label of the field that picks the photo.
    var title: String {
        switch self {
        case .appIcon: String(localized: "Icon")
        case .creditCard: String(localized: "Image")
        }
    }

    /// The crop screen's title.
    var cropTitle: String {
        switch self {
        case .appIcon: String(localized: "Crop Icon")
        case .creditCard: String(localized: "Crop Image")
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
                if let data, let image = CroppedPhoto.image(from: data) {
                    CroppedPhotoImage(image: image, shape: shape, height: 32)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(data == nil ? "Choose Photo" : "Replace")
                }
                if data != nil {
                    Button("Remove", role: .destructive) {
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
        .errorAlert("Couldn't Use Photo", message: $errorMessage)
    }

    /// Reads the chosen photo and opens the crop screen with it.
    private func load(_ item: PhotosPickerItem) async {
        pickerItem = nil
        do {
            guard let photoData = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = CroppedPhoto.decode(photoData) else {
                errorMessage = String(localized: "That photo can't be read.")
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
