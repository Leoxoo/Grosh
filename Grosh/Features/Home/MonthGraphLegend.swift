import SwiftUI

/// The legend under a Month graph tab's chart: a short stroke in each line's color and its name, the month as the
/// strip names it ("This month", "Last month", "07/2026") for the line in the tab's color and, while the chart has
/// one, "Average" or "Last year" for the gray line; then, at the right end, the "vs last year" switch. While the
/// chart has a dotted line, a row under them names it "Scheduled", with Expected by month end.
struct MonthGraphLegend: View {
    let graph: MonthGraph
    /// Whether the "vs last year" switch is on.
    @Binding var comparesWithLastYear: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                // Already localized: shown as they are.
                entry(Text(verbatim: graph.lineName), color: graph.side.color)
                if graph.comparisonLine != nil {
                    entry(Text(verbatim: graph.comparison.name), color: MonthGraphChart.comparisonColor)
                }
                Spacer(minLength: 0)
                if graph.offersLastYear {
                    Toggle(Strings.Home.vsLastYear, isOn: $comparesWithLastYear)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .fixedSize()
                        // Greyed out but left as set, so it applies again on a month with Last year.
                        .disabled(!graph.isLastYearAvailable)
                }
            }
            if let expected = graph.expectedByMonthEnd {
                entry(Text(Strings.Home.scheduledExpectedBy(graph.endName, expected.formatted())), color: graph.side.color, dotted: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func entry(_ name: Text, color: Color, dotted: Bool = false) -> some View {
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
            name
        }
    }
}
