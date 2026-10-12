import Charts
import SwiftUI

/// The chart of a Month graph card: the running total as a line in the card's color across the whole month, from zero
/// at the left edge, and a marker with a popup on the selected day. A few days are named along the bottom; no amounts
/// are named up the side.
struct MonthGraphChart: View {
    let graph: MonthGraph

    /// Room above the plot for the popup, growing with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var popupHeight: CGFloat = 50

    var body: some View {
        let selected = graph.defaultSelection
        let popup = graph.popup(on: selected)
        Chart {
            RuleMark(x: .value("Day", graph.position(of: selected)))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    MonthGraphPopup(popup: popup)
                }

            ForEach(graph.line, id: \.position) { point in
                LineMark(x: .value("Day", point.position), y: .value("Total", Double(point.total.cents)))
            }
            .foregroundStyle(graph.side.color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if let total = popup.total {
                PointMark(x: .value("Day", graph.position(of: selected)), y: .value("Total", Double(total.cents)))
                    .foregroundStyle(graph.side.color)
            }
        }
        .chartXScale(domain: 0.0...1.0)
        .chartYScale(domain: totalsDomain)
        .chartXAxis {
            AxisMarks(values: labeledDays.map(graph.position(of:))) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text(labeledDays[value.index].day, format: .number)
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
            }
        }
        // The headline already says the amount so far, and the line's positions mean nothing read aloud.
        .accessibilityHidden(true)
        .frame(height: 150)
        .padding(.top, popupHeight)
    }

    /// The days named along the bottom: every seventh day from the 1st.
    private var labeledDays: [CalendarDay] {
        stride(from: 1, through: graph.month.dayCount, by: 7).map {
            CalendarDay(year: graph.month.year, month: graph.month.month, day: $0)
        }
    }

    /// From zero, or below it when refunds take Spent under zero, to the highest total. A flat line at zero sits at the
    /// bottom.
    private var totalsDomain: ClosedRange<Double> {
        let totals = graph.line.map { Double($0.total.cents) }
        let lowest = min(totals.min() ?? 0, 0)
        return lowest...max(totals.max() ?? 0, lowest + 1)
    }
}

/// The popup over the marker: the selected day's date and the running total through it.
private struct MonthGraphPopup: View {
    let popup: MonthGraph.Popup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(popup.day.date().formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let total = popup.total {
                Text(total.formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}
