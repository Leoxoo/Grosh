import Charts
import SwiftUI

/// The chart of a Month graph tab: the running total as a line in the tab's color across the whole month, from zero
/// at the left edge, over the gray line it is compared with, then dotted from today to the month's end with what is
/// still scheduled, and a marker with a popup on the selected day. Scrubbing across the chart moves the marker from day
/// to day. A few days are named along the bottom, and a few amounts up the right side, shortened as in "5K".
struct MonthGraphChart: View {
    /// The gray of the line the month is compared with, the Average or Last year, which the legend matches.
    static let comparisonColor = Color.gray
    /// The dots of the line of what is still scheduled, which the legend matches.
    static let scheduledStroke = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [0, 5])

    let graph: MonthGraph
    /// The day the marker and popup are on.
    @Binding var selection: CalendarDay

    /// Room above the plot for the popup, growing with the text size.
    @ScaledMetric(relativeTo: .subheadline) private var popupHeight: CGFloat = 66
    /// More room above the plot for each Occurrence the popup lists.
    @ScaledMetric(relativeTo: .caption) private var occurrenceHeight: CGFloat = 16

    var body: some View {
        let popup = graph.popup(on: selection)
        Chart {
            RuleMark(x: .value(Strings.Common.day, graph.position(of: selection)))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    MonthGraphPopup(popup: popup, comparisonName: graph.comparison.name)
                }

            if let comparisonLine = graph.comparisonLine {
                line(comparisonLine, series: "Comparison")
                    .foregroundStyle(Self.comparisonColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            line(graph.line, series: "Month")
                .foregroundStyle(graph.side.color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if let scheduledLine = graph.scheduledLine {
                // In steps, so each payment rises on its own due day instead of sloping across it.
                line(scheduledLine, series: "Scheduled")
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(graph.side.color)
                    .lineStyle(Self.scheduledStroke)
            }

            if let comparison = popup.comparison {
                marker(at: comparison)
                    .foregroundStyle(Self.comparisonColor)
            }
            // On the line through today, or on the dotted line after it.
            if let total = popup.total ?? popup.expected {
                marker(at: total)
                    .foregroundStyle(graph.side.color)
            }
        }
        .chartXScale(domain: 0.0...1.0)
        .chartYScale(domain: totalsDomain)
        .chartXAxis {
            AxisMarks(values: labeledDays.map { graph.position(of: $0) }) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text(labeledDays[value.index].day, format: .number)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let cents = value.as(Double.self) {
                        Text(Money(cents: Int(cents.rounded())).decimalValue, format: .number.notation(.compactName))
                    }
                }
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
        .padding(.top, popupHeight + occurrenceHeight * CGFloat(mostScheduledOnADay))
    }

    /// `points` joined into one line, kept apart from the chart's other lines by `series`.
    private func line(_ points: [MonthGraph.Point], series: String) -> some ChartContent {
        ForEach(points, id: \.position) { point in
            LineMark(
                x: .value(Strings.Common.day, point.position),
                y: .value(Strings.Common.total, Double(point.total.cents)),
                series: .value(Strings.Common.line, series)
            )
        }
    }

    /// A dot on the selected day at `total`.
    private func marker(at total: Money) -> some ChartContent {
        PointMark(x: .value(Strings.Common.day, graph.position(of: selection)), y: .value(Strings.Common.total, Double(total.cents)))
    }

    /// The days named along the bottom: every seventh day from the 1st.
    private var labeledDays: [CalendarDay] {
        stride(from: 1, through: graph.span.dayCount, by: 7).map { graph.span.day($0) }
    }

    /// The most Occurrences the popup lists on any one day, which the room above the plot is kept for, so the plot
    /// stays put as the marker moves.
    private var mostScheduledOnADay: Int {
        (1...graph.span.dayCount).map { graph.popup(on: graph.span.day($0)).scheduled.count }.max() ?? 0
    }

    /// From zero, or below it when refunds take Spent under zero, to the highest total of any line, and at least one
    /// whole unit of money tall, so a flat line at zero sits at the bottom of an axis that reads in whole amounts.
    private var totalsDomain: ClosedRange<Double> {
        let lines = graph.line + (graph.comparisonLine ?? []) + (graph.scheduledLine ?? [])
        let totals = lines.map { Double($0.total.cents) }
        let lowest = min(totals.min() ?? 0, 0)
        return lowest...max(totals.max() ?? 0, lowest + 100)
    }

    /// Moves the marker to the day nearest `x`, a position across the overlay `geometry` measures.
    private func select(atX x: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame,
              let position = proxy.value(atX: x - geometry[plotFrame].origin.x, as: Double.self)
        else { return }
        selection = graph.day(nearest: position)
    }
}

/// The popup over the marker: the selected day's date, the running total through it or, on a day still to come, the
/// total expected by then and what is scheduled that day, and the gray line's total there under the legend's name for
/// it.
private struct MonthGraphPopup: View {
    let popup: MonthGraph.Popup
    /// What the legend calls the gray line: "Average" or "Last year".
    let comparisonName: String

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
            if let expected = popup.expected {
                Text(Strings.Home.expected(expected.formatted()))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ForEach(popup.scheduled) { occurrence in
                // Each counts toward the tab, by what it adds to the tab's total.
                if let counted = occurrence.countedAmount {
                    Text("\(occurrence.recurring.name) \(counted.amount.formatted())")
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            if let comparison = popup.comparison {
                // The name is already localized: shown as it is.
                Text("\(comparisonName) \(comparison.formatted())")
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
