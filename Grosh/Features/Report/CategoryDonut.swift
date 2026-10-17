import SwiftUI

/// A donut of one side's parent categories: a slice per ``CategoryBreakdown/Slice`` in its category's color, or the
/// Everything else gray. Each slice's icon sits outside the ring on a stick, with its percent beside it in the slice's
/// color. VoiceOver reads each icon as the category's name and its share. With nothing above zero it is an empty ring.
struct CategoryDonut: View {
    let breakdown: CategoryBreakdown

    /// The room the labels take beyond the ring: the stick, the icon and its percent.
    private let labelReach: CGFloat = 54
    /// The icon's radius.
    private let iconRadius: CGFloat = 11
    /// The stick's length, from the ring's edge out to the icon.
    private let stickLength: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = max(side / 2 - labelReach, 18)
            let ringWidth = max(6, radius * 0.32)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ring(radius: radius, ringWidth: ringWidth)
                Canvas { context, _ in
                    for placed in placedSlices {
                        var stick = Path()
                        stick.move(to: point(from: center, distance: radius + 2, angle: placed.angle))
                        stick.addLine(to: point(from: center, distance: radius + stickLength, angle: placed.angle))
                        context.stroke(stick, with: .color(placed.color), lineWidth: 1.5)
                    }
                }
                ForEach(Array(placedSlices.enumerated()), id: \.offset) { _, placed in
                    let iconCenter = point(from: center, distance: radius + stickLength + iconRadius, angle: placed.angle)
                    icon(for: placed.slice)
                        .position(iconCenter)
                    percent(for: placed)
                        .position(percentCenter(besideIconAt: iconCenter, angle: placed.angle))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The ring: each slice's arc, or an empty ring when no slice has anything in it.
    @ViewBuilder
    private func ring(radius: CGFloat, ringWidth: CGFloat) -> some View {
        if placedSlices.isEmpty {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: ringWidth)
                .frame(width: (radius - ringWidth / 2) * 2, height: (radius - ringWidth / 2) * 2)
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
            CategoryIcon(category: total.category, size: iconRadius * 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.label(total.category.name, share: breakdown.share(of: total.total)))
        case .everythingElse(let amount):
            SymbolCircle(symbolName: "ellipsis", color: .gray, size: iconRadius * 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.label(String(localized: "Everything else"), share: breakdown.share(of: amount)))
        }
    }

    /// The slice's share beside its icon, in the slice's color. VoiceOver reads it with the icon, so it is hidden.
    private func percent(for placed: PlacedSlice) -> some View {
        Text(breakdown.share(of: placed.amount).formatted(.percent.precision(.fractionLength(0))))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(placed.color)
            .accessibilityHidden(true)
    }

    /// Where the percent sits: just outside its icon, along the icon's direction from the donut's center, clear of the icon
    /// by the room its text takes in that direction.
    private func percentCenter(besideIconAt iconCenter: CGPoint, angle: Double) -> CGPoint {
        let horizontal = abs(sin(angle)), vertical = abs(cos(angle))
        let reach = iconRadius + 3 + horizontal * 14 + vertical * 6
        return point(from: iconCenter, distance: reach, angle: angle)
    }

    private static func label(_ name: String, share: Double) -> String {
        "\(name), \(share.formatted(.percent.precision(.fractionLength(0))))"
    }

    /// A point `distance` from `center` at `angle` radians clockwise from the top.
    private func point(from center: CGPoint, distance: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + distance * sin(angle), y: center.y - distance * cos(angle))
    }

    /// Where a slice sits: its arc as fractions of the way round, clockwise from the top, and the angle its icon sits at.
    private struct PlacedSlice {
        let slice: CategoryBreakdown.Slice
        let start: Double
        let end: Double
        /// The middle of the arc, in radians clockwise from the top.
        var angle: Double { (start + end) / 2 * 2 * .pi }
        var amount: Money { slice.amount }
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
