import CoreGraphics
import SwiftUI

/// Crops a picked photo to a ``CropShape``: a Subscription's app-icon square or a Card's credit-card rectangle. A fixed
/// window stays put while the photo moves beneath it: drag to move the photo, pinch or use the slider to zoom. Save
/// keeps what the window shows.
struct PhotoCropView: View {
    let photo: CGImage
    let shape: CropShape
    /// Receives the cropped photo's JPEG data once the user saves.
    let onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The crop as the last gesture left it. A gesture still under way is layered over it.
    @State private var committed: PhotoCrop
    @State private var errorMessage: String?
    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var pinchFactor: CGFloat = 1

    /// The window's width in points, and its height in the shape's proportions.
    private var windowWidth: CGFloat { shape == .appIcon ? 260 : 300 }
    private var windowHeight: CGFloat { windowWidth / shape.aspect }

    init(photo: CGImage, shape: CropShape, onSave: @escaping (Data) -> Void) {
        self.photo = photo
        self.shape = shape
        self.onSave = onSave
        _committed = State(initialValue: .centered(on: CGSize(width: photo.width, height: photo.height), shape: shape))
    }

    private var photoSize: CGSize {
        CGSize(width: photo.width, height: photo.height)
    }

    /// The window's shape, the same one the photo is drawn in.
    private var windowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: windowHeight * shape.cornerRatio, style: .continuous)
    }

    /// The crop the window shows right now, with any gesture under way applied.
    private var crop: PhotoCrop {
        PhotoCrop(zoom: committed.zoom * pinchFactor, center: committed.center, shape: shape)
            .clamped(to: photoSize)
            .panned(by: dragTranslation, windowWidth: windowWidth, in: photoSize)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                cropWindow
                Slider(value: zoomBinding, in: PhotoCrop.zoomRange)
                    .frame(width: windowWidth)
                    .accessibilityLabel(Strings.Photos.zoom)
                Text(Strings.Photos.cropHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(shape.cropTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel, role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.save, action: save)
                }
            }
            .errorAlert(Strings.Photos.couldntSave, message: $errorMessage)
        }
    }

    /// The photo, scaled so the window shows exactly `crop` and offset so the crop's center falls under the window's
    /// center, clipped to the window's shape.
    private var cropWindow: some View {
        let pointsPerPixel = windowWidth / crop.size(in: photoSize).width
        let shown = CGSize(width: photoSize.width * pointsPerPixel, height: photoSize.height * pointsPerPixel)
        let offset = CGSize(
            width: (photoSize.width / 2 - crop.center.x) * pointsPerPixel,
            height: (photoSize.height / 2 - crop.center.y) * pointsPerPixel
        )
        return Image(decorative: photo, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: shown.width, height: shown.height)
            .offset(offset)
            .frame(width: windowWidth, height: windowHeight)
            .contentShape(Rectangle())
            .clipShape(windowShape)
            .overlay {
                windowShape.strokeBorder(.white, lineWidth: 2)
            }
            .gesture(pan)
            .simultaneousGesture(pinch)
    }

    /// Dragging moves the photo under the window.
    private var pan: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                committed = committed.panned(by: value.translation, windowWidth: windowWidth, in: photoSize)
            }
    }

    /// Pinching zooms in on the middle of the photo.
    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($pinchFactor) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                committed = PhotoCrop(
                    zoom: committed.zoom * value.magnification, center: committed.center, shape: shape
                )
                .clamped(to: photoSize)
            }
    }

    /// The slider's zoom, which keeps the crop's center.
    private var zoomBinding: Binding<CGFloat> {
        Binding(
            get: { committed.zoom },
            set: { committed = PhotoCrop(zoom: $0, center: committed.center, shape: shape).clamped(to: photoSize) }
        )
    }

    private func save() {
        guard let data = CroppedPhoto.jpegData(cropping: photo, to: crop) else {
            errorMessage = String(localized: Strings.Photos.couldntCrop)
            return
        }
        onSave(data)
        dismiss()
    }
}
