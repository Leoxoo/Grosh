import SwiftUI

/// How far a tab's first screen has scrolled from the top of its list: negative while it is pulled down past it. Its own
/// object, so that only what moves with the scroll, the title and Transactions' header, reads it on each frame, and the
/// list isn't drawn again.
@Observable
final class TabRootScroll {
    /// How far the list scrolls while the title fades away, and Transactions' header rises into its place.
    static let titleRise: CGFloat = 44

    var offset: CGFloat = 0

    /// From 0 with the list at its top to 1 once it has scrolled ``titleRise``.
    var progress: CGFloat { min(1, max(0, offset / Self.titleRise)) }

    /// How far the list is pulled down past its top, or 0.
    var pull: CGFloat { max(0, -offset) }
}

extension View {
    /// Keeps `scroll` up to date with this list's scroll. Apply it to the list itself, so a scroll view inside a row or
    /// a header, such as a period strip, doesn't count.
    func tracksTabRootScroll(_ scroll: TabRootScroll) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scroll.offset = offset
        }
    }

    /// The title of a tab's first screen, in the large title's style on the row of the bar's buttons, as standard apps
    /// have it (ADR-0009). It fades as the list scrolls up and moves down with a pull. The bar shows no small title,
    /// unless `showsSmallTitle`, as while selecting, when it shows the count. Apply it to the screen's list, inside the
    /// tab's `NavigationStack`; a screen that moves something else with the scroll passes its own `scroll`, kept up to
    /// date with ``tracksTabRootScroll(_:)``.
    func tabRootTitle(
        _ title: LocalizedStringKey, scroll: TabRootScroll? = nil, showsSmallTitle: Bool = false
    ) -> some View {
        modifier(TabRootTitleModifier(title: title, given: scroll, showsSmallTitle: showsSmallTitle))
    }
}

private struct TabRootTitleModifier: ViewModifier {
    let title: LocalizedStringKey
    let given: TabRootScroll?
    let showsSmallTitle: Bool
    @State private var own = TabRootScroll()

    func body(content: Content) -> some View {
        #if os(iOS)
        let scroll = given ?? own
        content
            .modifier(TrackingUnlessGiven(scroll: own, isGiven: given != nil))
            .navigationBarTitleDisplayMode(.inline)
            // Removed rather than covered with an empty item, which would hold the bar's middle and leave the large
            // title half the bar.
            .toolbar(removing: showsSmallTitle ? nil : .title)
            .toolbar {
                if !showsSmallTitle {
                    ToolbarItem(placement: .topBarLeading) {
                        TabRootTitleText(title: title, scroll: scroll)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        #else
        content
        #endif
    }
}

/// Tracks the list's scroll into the modifier's own object, unless the screen passed one it keeps up to date itself.
private struct TrackingUnlessGiven: ViewModifier {
    let scroll: TabRootScroll
    let isGiven: Bool

    func body(content: Content) -> some View {
        if isGiven {
            content
        } else {
            content.tracksTabRootScroll(scroll)
        }
    }
}

/// The title itself: the large title's font, fading out as the list leaves its top and moving down with a pull.
private struct TabRootTitleText: View {
    let title: LocalizedStringKey
    let scroll: TabRootScroll

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .lineLimit(1)
            .fixedSize()
            .opacity(1 - scroll.progress)
            .offset(y: scroll.pull)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isHeader)
    }
}
