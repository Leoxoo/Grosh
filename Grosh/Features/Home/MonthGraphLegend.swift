import SwiftUI

/// The legend under a Month graph card's chart: a short stroke in each line's color and its name, the month as the
/// strip names it ("This month", "Last month", "07/2026") for the line in the card's color and, while the chart has
/// one, "Average" for the gray line. While the chart has a dotted line, a row under them names it "Scheduled", with
/// Expected by month end.
struct MonthGraphLegend: View {
    let graph: MonthGraph

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                // Already localized: shown as it is.
                entry("\(graph.lineName)", color: graph.side.color)
                if graph.averageLine != nil {
                    entry("Average", color: MonthGraphChart.averageColor)
                }
            }
            if let expected = graph.expectedByMonthEnd {
                entry("Scheduled · Expected by month end \(expected.formatted())", color: graph.side.color, dotted: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func entry(_ name: LocalizedStringKey, color: Color, dotted: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dotted {
                Path { path in
                    path.move(to: CGPoint(x: 1.5, y: 1.5))
                    path.addLine(to: CGPoint(x: 11.5, y: 1.5))
                }
                .stroke(color, style: MonthGraphChart.scheduledStroke)
                .frame(width: 12, height: 3)
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: 12, height: 3)
            }
            Text(name)
        }
    }
}
