import SwiftUI

extension View {
    /// Styles a short label as the small capsule a row marks a transaction with (Scheduled, Estimated, Forgiven): one
    /// line in a small medium font, in `foreground`, on a tint of `color`.
    func capsuleBadge(_ foreground: some ShapeStyle, on color: Color) -> some View {
        font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(color.opacity(0.15), in: Capsule())
    }
}
