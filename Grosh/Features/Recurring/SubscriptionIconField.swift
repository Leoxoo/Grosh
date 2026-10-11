import CoreGraphics
import PhotosUI
import SwiftUI

/// A Subscription's optional icon, as the Recurring form offers it: the current icon, and buttons to choose a photo or
/// remove the icon. A chosen photo opens ``SubscriptionIconCropView``, and the icon is kept only once it is saved there.
struct SubscriptionIconField: View {
    @Binding var iconData: Data?

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedPhoto: PickedPhoto?
    @State private var errorMessage: String?

    var body: some View {
        LabeledContent("Icon") {
            HStack(spacing: 12) {
                if let iconData, let image = SubscriptionIcon.image(from: iconData) {
                    SubscriptionIconImage(image: image, size: 32)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(iconData == nil ? "Choose Photo" : "Replace")
                }
                if iconData != nil {
                    Button("Remove", role: .destructive) {
                        iconData = nil
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .sheet(item: $pickedPhoto) { picked in
            SubscriptionIconCropView(photo: picked.image) { data in
                iconData = data
            }
        }
        .errorAlert("Couldn't Use Photo", message: $errorMessage)
    }

    /// Reads the chosen photo and opens the crop screen with it.
    private func load(_ item: PhotosPickerItem) async {
        pickerItem = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = SubscriptionIcon.decode(data) else {
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
