import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    /// Calls `action` with how far across the view, in its own coordinates, the user is scrubbing: dragging sideways on
    /// iPhone and iPad, and on Mac moving the pointer over the view or click-dragging. A pointer over it on iPad scrubs
    /// too. Letting go or moving the pointer away calls nothing, so whatever `action` last picked stays.
    ///
    /// A drag that starts out up or down is left to the list the view sits in, so the list still scrolls. Mac lists
    /// scroll with the trackpad or mouse wheel rather than a drag, so there a plain drag takes nothing from the list.
    func onScrub(perform action: @escaping (CGFloat) -> Void) -> some View {
        onContinuousHover { phase in
            if case .active(let location) = phase {
                action(location.x)
            }
        }
        #if os(iOS)
        .gesture(HorizontalPan(action: action))
        #else
        .gesture(DragGesture(minimumDistance: 0).onChanged { action($0.location.x) })
        #endif
    }
}

#if os(iOS)
/// A pan that begins only when the finger starts out moving more sideways than up or down. A SwiftUI drag can't turn
/// down a vertical start, so inside a list it would take the list's scrolling; this pan turns it down, and the list's
/// own pan waits until it has, so a sideways drag never scrolls the list either.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let action: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if recognizer.state == .began || recognizer.state == .changed {
            action(context.converter.localLocation.x)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer === (otherGestureRecognizer.view as? UIScrollView)?.panGestureRecognizer
        }
    }
}
#endif
