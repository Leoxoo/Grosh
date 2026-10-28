import SwiftUI

/// How far a tab's first screen has scrolled from the top of its list: negative while it is pulled down past it. Its own
/// object, so that only what moves with the scroll, the title and Transactions' header, reads it on each frame, and the
/// list isn't drawn again.
@Observable
final class TabRootScroll {
    /// How far the list scrolls while the title fades away, and a header that rises with it moves up.
    let rise: CGFloat

    var offset: CGFloat = 0

    init(rise: CGFloat = 44) {
        self.rise = rise
    }

    /// From 0 with the list at its top to 1 once it has scrolled ``rise``.
    var progress: CGFloat { min(1, max(0, offset / rise)) }

    /// Whether the title has gone and a rising header has reached the bar.
    var isRisen: Bool { progress >= 1 }

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
        tabRootTitle(title, scroll: scroll, showsSmallTitle: showsSmallTitle) { EmptyView() }
    }

    /// ``tabRootTitle(_:scroll:showsSmallTitle:)`` that puts `risen` in the title's place once the list has scrolled
    /// `scroll`'s ``TabRootScroll/rise``: the part of a rising header that has reached the bar, shown there so that taps
    /// reach it, as the bar's row takes the taps on what lies under it.
    func tabRootTitle<Risen: View>(
        _ title: LocalizedStringKey, scroll: TabRootScroll?, showsSmallTitle: Bool = false,
        @ViewBuilder risen: @escaping () -> Risen
    ) -> some View {
        modifier(TabRootTitleModifier(title: title, given: scroll, showsSmallTitle: showsSmallTitle, risen: risen))
    }
}

private struct TabRootTitleModifier<Risen: View>: ViewModifier {
    let title: LocalizedStringKey
    let given: TabRootScroll?
    let showsSmallTitle: Bool
    let risen: () -> Risen
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
                        TabRootLeadingItem(title: title, scroll: scroll, risen: risen)
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

/// The bar's leading item: the title in the large title's font, fading out as the list leaves its top and moving down
/// with a pull, and in its place, once the header has risen to the bar, the header's part that has reached it.
private struct TabRootLeadingItem<Risen: View>: View {
    let title: LocalizedStringKey
    let scroll: TabRootScroll
    let risen: () -> Risen

    var body: some View {
        ZStack(alignment: .leading) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .fixedSize()
                .opacity(1 - scroll.progress)
                .offset(y: scroll.pull)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(scroll.isRisen)
            // Made only once risen, so whatever it reads isn't read the rest of the time.
            if scroll.isRisen {
                risen()
            }
        }
    }
}

extension View {
    /// Hides the part of a rising header that ``tabRootTitle(_:scroll:showsSmallTitle:risen:)`` shows in the bar once
    /// it has reached it, so the two are never both there.
    func hiddenOnceRisen(_ scroll: TabRootScroll) -> some View {
        modifier(HiddenOnceRisen(scroll: scroll))
    }
}

private struct HiddenOnceRisen: ViewModifier {
    let scroll: TabRootScroll

    func body(content: Content) -> some View {
        content
            .opacity(scroll.isRisen ? 0 : 1)
            .allowsHitTesting(!scroll.isRisen)
            .accessibilityHidden(scroll.isRisen)
    }
}
