import SwiftUI

/// The legend under a Month graph card's chart: a short stroke in each line's color and its name, "This month" for the
/// line in the card's color and, while the chart has one, "Average" for the gray line.
struct MonthGraphLegend: View {
    let graph: MonthGraph

    var body: some View {
        HStack(spacing: 16) {
            entry("This month", color: graph.side.color)
            if graph.averageLine != nil {
                entry("Average", color: MonthGraphChart.averageColor)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func entry(_ name: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 12, height: 3)
            Text(name)
        }
    }
}
