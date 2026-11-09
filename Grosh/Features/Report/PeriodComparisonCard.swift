import Foundation
import SwiftUI

/// The comparison card of Income and Spent details, between the totals and the Breakdown | Trend control. Collapsed, it shows
/// the Average's running total at the same point in the period (today for the current period, the end of a past one) with a
/// Show button. Shown, it draws the side's running total for the Wallet selector's choice against the gray Average, with
/// Home's legend, the "vs last year" switch for a month, and a Hide button. Whether it is shown is remembered between launches.
struct PeriodComparisonCard: View {
    let graph: MonthGraph
    /// Whether the "vs last year" switch, which Home's Month graph shares, is on.
    @Binding var comparesWithLastYear: Bool

    @AppStorage(AppSettings.isComparisonCardShownKey) private var isShown = AppSettings.isComparisonCardShownDefault
    /// The day the user last moved the marker to, or `nil` until they move it.
    @State private var scrubbedDay: CalendarDay?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isShown {
                    MonthGraphChart(graph: graph, selection: selection)
                    MonthGraphLegend(graph: graph, comparesWithLastYear: $comparesWithLastYear)
                        .padding(.top, 4)
                } else {
                    collapsedValue
                }
            }
            .padding(.vertical, 4)
            .onChange(of: graph.span) { scrubbedDay = nil }
        }
    }

    /// The card's title with its ⓘ, and the Show or Hide button on the trailing edge.
    private var header: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ExplanationButton(label: Strings.Report.whatTheAverageIs, explanation: explanation)
            Spacer()
            Button(isShown ? Strings.Common.hide : Strings.Common.show) {
                withAnimation { isShown.toggle() }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
    }

    /// The Average's running total at the same point in the period as the line reaches: today, or the end of a past period.
    private var collapsedValue: some View {
        HStack {
            Text(graph.popup(on: graph.defaultSelection).comparison?.formatted() ?? "")
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// The day the marker and popup are on: where the user left the marker, or the graph's default until they move it.
    private var selection: Binding<CalendarDay> {
        Binding(get: { scrubbedDay ?? graph.defaultSelection }, set: { scrubbedDay = $0 })
    }

    /// What the gray line is called in the card's title: Last year, or the Average with how many periods it takes.
    private var title: String {
        let count = MonthGraphComparison.averagePeriodCount
        switch graph.comparison {
        case .lastYear:
            return String(localized: Strings.Report.comparedToLastYear)
        case .average:
            switch graph.span.length {
            case .week: return String(localized: Strings.Report.comparedToWeekAverage(count))
            case .month: return String(localized: Strings.Report.comparedToMonthAverage(count))
            case .quarter: return String(localized: Strings.Report.comparedToQuarterAverage(count))
            case .year: return String(localized: Strings.Report.comparedToYearAverage(count))
            }
        }
    }

    /// What the Average is, in one sentence, its period count spelled out.
    private var explanation: String {
        let spelling = NumberFormatter()
        spelling.numberStyle = .spellOut
        let count = MonthGraphComparison.averagePeriodCount
        return String(localized: Strings.Report.averageExplanation(spelling.string(from: count as NSNumber) ?? "\(count)"))
    }
}
