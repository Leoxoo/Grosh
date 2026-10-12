import Charts
import SwiftUI

/// The chart of a Month graph card: the running total as a line in the card's color across the whole month, from zero
/// at the left edge, over the gray line of the Average, and a marker with a popup on the selected day. Scrubbing across
/// the chart moves the marker from day to day. A few days are named along the bottom; no amounts are named up the side.
struct MonthGraphChart: View {
    /// The gray of the Average's line, which the legend matches.
    static let averageColor = Color.gray

    let graph: MonthGraph
    /// The day the marker and popup are on.
    @Binding var selection: CalendarDay

    /// Room above the plot for the popup, growing with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var popupHeight: CGFloat = 66

    var body: some View {
        let popup = graph.popup(on: selection)
        Chart {
            RuleMark(x: .value("Day", graph.position(of: selection)))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    MonthGraphPopup(popup: popup)
                }

            if let averageLine = graph.averageLine {
                ForEach(averageLine, id: \.position) { point in
                    LineMark(
                        x: .value("Day", point.position),
                        y: .value("Total", Double(point.total.cents)),
                        series: .value("Line", "Average")
                    )
                }
                .foregroundStyle(Self.averageColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(graph.line, id: \.position) { point in
                LineMark(
                    x: .value("Day", point.position),
                    y: .value("Total", Double(point.total.cents)),
                    series: .value("Line", "This month")
                )
            }
            .foregroundStyle(graph.side.color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if let average = popup.average {
                PointMark(x: .value("Day", graph.position(of: selection)), y: .value("Total", Double(average.cents)))
                    .foregroundStyle(Self.averageColor)
            }
            if let total = popup.total {
                PointMark(x: .value("Day", graph.position(of: selection)), y: .value("Total", Double(total.cents)))
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onScrub { select(atX: $0, proxy: proxy, geometry: geometry) }
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

    /// From zero, or below it when refunds take Spent under zero, to the highest total of either line. A flat line at
    /// zero sits at the bottom.
    private var totalsDomain: ClosedRange<Double> {
        let totals = (graph.line + (graph.averageLine ?? [])).map { Double($0.total.cents) }
        let lowest = min(totals.min() ?? 0, 0)
        return lowest...max(totals.max() ?? 0, lowest + 1)
    }

    /// Moves the marker to the day nearest `x`, a position across the overlay `geometry` measures.
    private func select(atX x: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotOriginX = geometry[proxy.plotAreaFrame].origin.x
        guard let position = proxy.value(atX: x - plotOriginX, as: Double.self) else { return }
        selection = graph.day(nearest: position)
    }
}

/// The popup over the marker: the selected day's date, the running total through it, and the Average there.
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
            if let average = popup.average {
                Text("Average \(average.formatted())")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}
