import CoreGraphics
import SwiftUI

/// Crops a picked photo to a Subscription's icon. A fixed app-icon-shaped window stays put while the photo moves beneath
/// it: drag to move the photo, pinch or use the slider to zoom. Save keeps what the window shows.
struct SubscriptionIconCropView: View {
    let photo: CGImage
    /// Receives the cropped icon's JPEG data once the user saves.
    let onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The crop as the last gesture left it. A gesture still under way is layered over it.
    @State private var committed: IconCrop
    @State private var errorMessage: String?
    @GestureState private var dragTranslation = CGSize.zero
    @GestureState private var pinchFactor: CGFloat = 1

    /// The window's side in points.
    private static let windowSide: CGFloat = 260

    init(photo: CGImage, onSave: @escaping (Data) -> Void) {
        self.photo = photo
        self.onSave = onSave
        _committed = State(initialValue: .centered(on: CGSize(width: photo.width, height: photo.height)))
    }

    private var photoSize: CGSize {
        CGSize(width: photo.width, height: photo.height)
    }

    /// The window's shape, the same one the icon is drawn in.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.windowSide * SubscriptionIcon.cornerRatio, style: .continuous)
    }

    /// The crop the window shows right now, with any gesture under way applied.
    private var crop: IconCrop {
        IconCrop(zoom: committed.zoom * pinchFactor, center: committed.center)
            .clamped(to: photoSize)
            .panned(by: dragTranslation, windowSide: Self.windowSide, in: photoSize)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                cropWindow
                Slider(value: zoomBinding, in: IconCrop.zoomRange)
                    .frame(width: Self.windowSide)
                    .accessibilityLabel("Zoom")
                Text("Drag to move the photo. Pinch, or use the slider, to zoom.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Crop Icon")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .errorAlert("Couldn't Save Icon", message: $errorMessage)
        }
    }

    /// The photo, scaled so the window shows exactly `crop` and offset so the crop's center falls under the window's
    /// center, clipped to the window's shape.
    private var cropWindow: some View {
        let pointsPerPixel = Self.windowSide / crop.side(in: photoSize)
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
            .frame(width: Self.windowSide, height: Self.windowSide)
            .contentShape(Rectangle())
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white, lineWidth: 2)
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
                committed = committed.panned(by: value.translation, windowSide: Self.windowSide, in: photoSize)
            }
    }

    /// Pinching zooms in on the middle of the photo.
    private var pinch: some Gesture {
        MagnifyGesture()
            .updating($pinchFactor) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                committed = IconCrop(zoom: committed.zoom * value.magnification, center: committed.center)
                    .clamped(to: photoSize)
            }
    }

    /// The slider's zoom, which keeps the crop's center.
    private var zoomBinding: Binding<CGFloat> {
        Binding(
            get: { committed.zoom },
            set: { committed = IconCrop(zoom: $0, center: committed.center).clamped(to: photoSize) }
        )
    }

    private func save() {
        guard let data = SubscriptionIcon.jpegData(cropping: photo, to: crop) else {
            errorMessage = String(localized: "The photo couldn't be cropped.")
            return
        }
        onSave(data)
        dismiss()
    }
}
