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
                entry("\(graph.lineName)", color: graph.side.color)
                if graph.comparisonLine != nil {
                    entry("\(graph.comparison.name)", color: MonthGraphChart.comparisonColor)
                }
                Spacer(minLength: 0)
                if graph.offersLastYear {
                    Toggle("vs last year", isOn: comparesWithoutAnimation)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .fixedSize()
                        // Greyed out but left as set, so it applies again on a month with Last year.
                        .disabled(!graph.isLastYearAvailable)
                }
            }
            if let expected = graph.expectedByMonthEnd {
                entry("Scheduled · Expected by \(graph.endName) \(expected.formatted())", color: graph.side.color, dotted: true)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The switch's setting, changed with every animation off. Home, the Report's comparison card and the Spent and
    /// Income details all redraw from it, some on screens not showing; an animation carried into those while the user
    /// leaves for another tab drew "Transformers don't support animations across multiple screens".
    private var comparesWithoutAnimation: Binding<Bool> {
        Binding {
            comparesWithLastYear
        } set: { isOn in
            var transaction = SwiftUI.Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { comparesWithLastYear = isOn }
        }
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
