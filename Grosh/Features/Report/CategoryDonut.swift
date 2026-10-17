import SwiftUI

/// A donut of one side's parent categories. Each slice's icon sits on a circle around the ring, evenly spaced in the slices'
/// order so no icon lies on another, with a stick from the icon to the middle of its slice and its percent beside it in the
/// slice's color.
/// VoiceOver reads each icon as the category's name and its share. With nothing above zero it is an empty ring.
struct CategoryDonut: View {
    let breakdown: CategoryBreakdown
    /// How many parent categories get a slice of their own before the rest share Everything else: the top five on the Report,
    /// and every parent in the details.
    var ownSliceLimit = CategoryBreakdown.ownSliceCount
    /// The smallest share of the side a category can be and still get a slice of its own; smaller ones share Everything else.
    var minimumShare: Double = 0
    /// How far the icons' circle sits outside the ring's outer edge: room for the stick. A small donut takes a shorter one.
    var stickLength: CGFloat = 38

    /// The icon's radius.
    private let iconRadius: CGFloat = 11
    /// The gap between an icon and its percent.
    private let gap: CGFloat = 4
    /// The room a percent takes beside its icon, wide enough for "100%".
    private let percentWidth: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            // The circle the icons sit on leaves room outside it for each icon and its percent.
            let iconCircle = max(side / 2 - iconRadius - gap - percentWidth, stickLength + 16)
            let radius = max(iconCircle - stickLength, 14)
            let ringWidth = max(8, radius * 0.3)
            let labels = placedLabels(center: center, iconCircle: iconCircle, ringEnd: radius - ringWidth / 2)
            ZStack {
                ring(radius: radius, ringWidth: ringWidth)
                Canvas { context, _ in
                    for label in labels {
                        var stick = Path()
                        stick.move(to: label.icon)
                        stick.addLine(to: label.ringEnd)
                        context.stroke(stick, with: .color(label.color), lineWidth: 1.5)
                    }
                }
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    icon(for: label.slice)
                        .position(label.icon)
                    Text(label.percent)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(label.color)
                        .accessibilityHidden(true)
                        .position(label.percentCenter)
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

    /// Each slice's icon, stick and percent, in the donut's own coordinates: the icons spread around `iconCircle`, and each
    /// stick runs from its icon to the middle of its slice on the ring, which ends at `ringEnd`.
    private func placedLabels(center: CGPoint, iconCircle: CGFloat, ringEnd: CGFloat) -> [Label] {
        let arcs = placedSlices
        let angles = Self.evenlySpaced(arcs.map(\.angle))
        return zip(arcs, angles).map { arc, angle in
            let icon = point(from: center, distance: iconCircle, angle: angle)
            // The percent sits outward from its icon, clear of the icon by its own half-size in that direction.
            let reach = iconRadius + gap + abs(sin(angle)) * percentWidth / 2 + abs(cos(angle)) * 6
            return Label(
                slice: arc.slice, color: arc.color,
                percent: breakdown.share(of: arc.amount).formatted(.percent.precision(.fractionLength(0))),
                icon: icon,
                ringEnd: point(from: center, distance: ringEnd, angle: arc.angle),
                percentCenter: point(from: icon, distance: reach, angle: angle)
            )
        }
    }

    /// The icons' angles: evenly spaced around the circle, in the slices' clockwise order, and turned as a whole so that on
    /// average each icon sits near its slice. Evenly spaced icons never lie on one another, and they stay in the donut's order.
    private static func evenlySpaced(_ middles: [Double]) -> [Double] {
        guard middles.count > 1 else { return middles }
        let count = Double(middles.count)
        let step = 2 * Double.pi / count
        let turn = middles.enumerated()
            .map { index, middle in middle - Double(index) * step }
            .reduce(0, +) / count
        return middles.indices.map { turn + Double($0) * step }
    }

    private static func label(_ name: String, share: Double) -> String {
        "\(name), \(share.formatted(.percent.precision(.fractionLength(0))))"
    }

    /// A point `distance` from `center` at `angle` radians clockwise from the top.
    private func point(from center: CGPoint, distance: CGFloat, angle: Double) -> CGPoint {
        CGPoint(x: center.x + distance * sin(angle), y: center.y - distance * cos(angle))
    }

    /// Where a slice sits on the ring: its arc as fractions of the way round, clockwise from the top.
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

    /// One slice's icon, stick and percent, in the donut's coordinates.
    private struct Label {
        let slice: CategoryBreakdown.Slice
        let color: Color
        let percent: String
        /// The icon's center.
        let icon: CGPoint
        /// Where the stick meets the ring: the middle of the slice's arc.
        let ringEnd: CGPoint
        /// The percent's center, beside the icon.
        let percentCenter: CGPoint
    }

    /// Every slice with its arc, the slices largest first, clockwise from the top. A sliver's gap to its neighbours is
    /// half a degree on each side, so neighbouring slices read as separate.
    private var placedSlices: [PlacedSlice] {
        let slices = breakdown.donutSlices(ownSliceLimit: ownSliceLimit, minimumShare: minimumShare)
        let amounts = slices.map { $0.amount.cents }
        let sum = amounts.reduce(0, +)
        guard sum > 0 else { return [] }
        var start = 0.0
        return zip(slices, amounts).map { slice, cents in
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
