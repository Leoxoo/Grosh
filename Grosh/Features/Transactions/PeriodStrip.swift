import SwiftUI

/// The row of periods above the transaction list: `… 08/2026 · Last month · This month · Future`, and of months alone
/// above Home's Month graph. It keeps the selected period's tab in view, scrolling it to the center whenever the
/// selection changes, and once the Current period's tab is scrolled out of view, a button at the trailing edge brings
/// it back. On Mac, holding and dragging scrolls it too. Lazy, since a day strip holds every day back to the first with
/// data.
struct PeriodStrip: View {
    let periods: [Period]
    @Binding var selection: Period
    /// The Current period, one of `periods`, which the return button brings back.
    let current: Period
    let today: CalendarDay

    @Environment(\.locale) private var locale
    /// Where the strip is scrolled to: the selected tab, or wherever the user scrolled since.
    @State private var position = ScrollPosition(idType: Period.self)
    /// Whether any part of the Current period's tab is on screen. While none is, the return button shows.
    @State private var isCurrentPeriodInView = true

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 20) {
                ForEach(periods, id: \.self) { period in
                    tab(for: period)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollPosition($position)
        // Hidden indicators still show on Mac while a mouse is connected or scroll bars are set to always show.
        .scrollIndicators(.never)
        // The bottom room `addTransactionButton()` gives a list on Mac reaches every scroll view under it, this one
        // included, and would add 88pt under the tabs.
        .contentMargins(.vertical, 0, for: .scrollContent)
        // A lazy stack would otherwise take all the height it is offered.
        .fixedSize(horizontal: false, vertical: true)
        .defaultScrollAnchor(.trailing)
        // Any part of the tab on screen counts as in view, so the button waits until the tab is fully gone. This is
        // called on every frame of a scroll, so it changes state, and starts the button's animation, only when the
        // answer changes.
        .onScrollTargetVisibilityChange(idType: Period.self, threshold: 0.001) { visible in
            let inView = visible.contains(current)
            guard inView != isCurrentPeriodInView else { return }
            withAnimation {
                isCurrentPeriodInView = inView
            }
        }
        .onAppear { scrollToSelection() }
        // A screen pushed onto a stack lays its strip out mid-transition, so the first scroll can land short of the trailing
        // end. Scrolling again once the transition has settled puts the selected tab in view.
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            scrollToSelection()
        }
        // A wallet with a different history moves the selected tab along the strip.
        .onChange(of: periods) { scrollToSelection() }
        .onChange(of: selection) { scrollToSelection(animated: true) }
        #if os(macOS)
        .modifier(DragToScroll(position: $position))
        #endif
        .overlay(alignment: .trailing) {
            if !isCurrentPeriodInView {
                returnButton(to: current)
            }
        }
        // Past AX1 a single tab can take most of an iPhone's width, so "Last month" and "This month" no longer fit
        // side by side and one is cut off at the edge.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func tab(for period: Period) -> some View {
        let isSelected = period == selection
        return Button {
            selection = period
        } label: {
            Text(period.title(today: today, locale: locale))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(.green)
                            .frame(height: 2)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The glass pill that selects the Current period and scrolls back to its tab: its name and a chevron, as in
    /// "This month ›".
    private func returnButton(to current: Period) -> some View {
        let title = current.title(today: today, locale: locale)
        return Button {
            // Only a change of selection scrolls on its own.
            if selection == current {
                scrollToSelection(animated: true)
            } else {
                selection = current
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityLabel("Back to \(title)")
        .padding(.trailing)
        .transition(.opacity)
    }

    /// Scrolls the selected tab to the center, stopping at the ends. Animated, it moves in one half-second ease however
    /// far away the tab is. The last tab is scrolled to the trailing end instead, so it is never cut off by the end of the
    /// strip, and the strip's own trailing padding shows past it.
    private func scrollToSelection(animated: Bool = false) {
        withAnimation(animated ? .easeInOut(duration: 0.5) : nil) {
            if selection == periods.last {
                position.scrollTo(edge: .trailing)
            } else {
                position.scrollTo(id: selection, anchor: .center)
            }
        }
    }
}

extension Period {
    /// Stays the period shown while `strip` still offers it; otherwise becomes `current`, the Current period. A strip
    /// of a wallet with a shorter history, or with the only transaction of its first period gone, may no longer offer
    /// it.
    mutating func showCurrentPeriod(_ current: Period, unlessOfferedBy strip: [Period]) {
        if !strip.contains(self) {
            self = current
        }
    }
}

#if os(macOS)
/// Holding and dragging the strip scrolls it, as touch does on iPhone and iPad, where a Mac would otherwise scroll it
/// only with a trackpad or mouse wheel. Letting go mid-drag glides a short way, never past either end.
private struct DragToScroll: ViewModifier {
    @Binding var position: ScrollPosition

    @State private var geometry: ScrollGeometry?
    /// Where the strip was scrolled to when the drag began.
    @State private var startOffset: CGFloat?

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in geometry = new }
            // The gaps between tabs start a drag too.
            .contentShape(.rect)
            // Takes over from the tab under the pointer once the drag passes a few points, so the drag doesn't select
            // it; a click without movement still does.
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { drag in
                        guard let geometry else { return }
                        let start = startOffset ?? geometry.contentOffset.x
                        startOffset = start
                        position.scrollTo(x: geometry.clampedOffset(start - drag.translation.width))
                    }
                    .onEnded { drag in
                        if let geometry, let start = startOffset {
                            let glideEnd = geometry.clampedOffset(start - drag.predictedEndTranslation.width)
                            withAnimation(.easeOut(duration: 0.5)) { position.scrollTo(x: glideEnd) }
                        }
                        startOffset = nil
                    }
            )
    }
}

private extension ScrollGeometry {
    /// `offset` held between the strip's leading and trailing ends.
    func clampedOffset(_ offset: CGFloat) -> CGFloat {
        let leadingEnd = -contentInsets.leading
        let trailingEnd = max(leadingEnd, contentSize.width + contentInsets.trailing - containerSize.width)
        return min(max(offset, leadingEnd), trailingEnd)
    }
}
#endif
