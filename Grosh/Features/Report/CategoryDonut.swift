import SwiftUI

/// A donut of one side's parent categories: a slice per ``CategoryBreakdown/Slice`` in its category's color, or the
/// Everything else gray, with the slice's icon beside it. No text or percentage sits on the donut; VoiceOver reads each
/// icon as the category's name and its share. With nothing above zero it is an empty ring.
struct CategoryDonut: View {
    let breakdown: CategoryBreakdown

    /// How thick the ring is.
    private let ringWidth: CGFloat = 16
    /// The icon beside each slice.
    private let iconSize: CGFloat = 24
    /// The gap between an icon and the ring, and the room the icons take beyond the ring.
    private let iconGap: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = max(side / 2 - iconSize - iconGap * 2, 0)
            let iconRadius = radius + iconGap + iconSize / 2
            ZStack {
                ring(radius: radius)
                ForEach(Array(placedSlices.enumerated()), id: \.offset) { _, placed in
                    icon(for: placed.slice)
                        .position(
                            x: side / 2 + iconRadius * sin(placed.angle),
                            y: side / 2 - iconRadius * cos(placed.angle)
                        )
                }
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The ring: each slice's arc, or an empty ring when no slice has anything in it.
    @ViewBuilder
    private func ring(radius: CGFloat) -> some View {
        if placedSlices.isEmpty {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: ringWidth)
                .frame(width: radius * 2 - ringWidth, height: radius * 2 - ringWidth)
        } else {
            ForEach(Array(placedSlices.enumerated()), id: \.offset) { _, placed in
                DonutSegment(
                    startFraction: placed.start, endFraction: placed.end,
                    innerRatio: max(radius - ringWidth, 0) / max(radius, 1)
                )
                .fill(placed.color)
                .frame(width: radius * 2, height: radius * 2)
                .accessibilityHidden(true)
            }
        }
    }

    /// The icon of one slice, read to VoiceOver as its name and share.
    @ViewBuilder
    private func icon(for slice: CategoryBreakdown.Slice) -> some View {
        switch slice {
        case .category(let total):
            CategoryIcon(category: total.category, size: iconSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.label(total.category.name, share: breakdown.share(of: total.total)))
        case .everythingElse(let amount):
            SymbolCircle(symbolName: "ellipsis", color: .gray, size: iconSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.label(String(localized: "Everything else"), share: breakdown.share(of: amount)))
        }
    }

    private static func label(_ name: String, share: Double) -> String {
        "\(name), \(share.formatted(.percent.precision(.fractionLength(0))))"
    }

    /// Where a slice sits: its arc as fractions of the way round, clockwise from the top, and the angle its icon sits at.
    private struct PlacedSlice {
        let slice: CategoryBreakdown.Slice
        let start: Double
        let end: Double
        /// The middle of the arc, in radians clockwise from the top.
        var angle: Double { (start + end) / 2 * 2 * .pi }
        var color: Color {
            switch slice {
            case .category(let total): total.category.color.color
            case .everythingElse: PaletteColor.gray.color
            }
        }
    }

    /// Every slice with its arc, the slices largest first, clockwise from the top. A sliver's gap to its neighbours is
    /// half a degree on each side, so neighbouring slices read as separate.
    private var placedSlices: [PlacedSlice] {
        let amounts = breakdown.slices.map { $0.amount.cents }
        let sum = amounts.reduce(0, +)
        guard sum > 0 else { return [] }
        var start = 0.0
        return zip(breakdown.slices, amounts).map { slice, cents in
            let end = start + Double(cents) / Double(sum)
            defer { start = end }
            return PlacedSlice(slice: slice, start: start, end: end)
        }
    }
}

/// An arc of a donut from one fraction of the way round to another, clockwise from the top, with a half-degree gap at
/// each end.
private struct DonutSegment: Shape {
    let startFraction: Double
    let endFraction: Double
    /// The inner radius as a share of the outer one.
    let innerRatio: CGFloat

    /// Half a degree, as a fraction of the way round.
    private static let halfGap = 0.5 / 360

    func path(in rect: CGRect) -> Path {
        let start = startFraction + Self.halfGap
        let end = endFraction - Self.halfGap
        guard end > start else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var path = Path()
        path.addArc(
            center: center, radius: outer,
            startAngle: Self.angle(start), endAngle: Self.angle(end), clockwise: false
        )
        path.addArc(
            center: center, radius: inner,
            startAngle: Self.angle(end), endAngle: Self.angle(start), clockwise: true
        )
        path.closeSubpath()
        return path
    }

    /// The angle of a fraction of the way round, measured as Path measures it, from the positive x axis: the top is -90°.
    private static func angle(_ fraction: Double) -> Angle {
        .degrees(fraction * 360 - 90)
    }
}
