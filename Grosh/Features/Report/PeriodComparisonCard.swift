import SwiftUI

/// The comparison card of Income and Spent details, between the totals and the Breakdown | Trend control. Collapsed, it shows
/// the Average's running total at the same point in the period (today for the current period, the end of a past one) with a
/// Show button. Shown, it draws the side's running total for the Wallet selector's choice against the gray Average, with
/// Home's legend, the "vs last year" switch for a month, and a Hide button. Whether it is shown is remembered between launches.
struct PeriodComparisonCard: View {
    let graph: MonthGraph
    /// Whether the "vs last year" switch, which Home's Month graph shares, is on.
    @Binding var comparesWithLastYear: Bool

    /// Remembers across launches whether the card is shown.
    @AppStorage("report.comparisonCard.isShown") private var isShown = false
    /// Whether the ⓘ explanation of the Average is showing.
    @State private var isExplaining = false
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
            Button {
                isExplaining = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("What the Average is")
            .popover(isPresented: $isExplaining) {
                Text(Self.explanation)
                    .font(.subheadline)
                    .padding()
                    .frame(maxWidth: 320, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
            Spacer()
            Button(isShown ? "Hide" : "Show") {
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

    /// What the gray line is called in the card's title.
    private var title: String {
        switch graph.comparison {
        case .lastYear:
            return String(localized: "Compared to last year")
        case .average:
            switch graph.period {
            case .week: return String(localized: "Compared to 3-Week Avg")
            case .month: return String(localized: "Compared to 3-Month Avg")
            case .quarter: return String(localized: "Compared to 3-Quarter Avg")
            case .year: return String(localized: "Compared to 3-Year Avg")
            case .day, .all, .custom, .future: return String(localized: "Compared to Average")
            }
        }
    }

    /// What the Average is, in one sentence.
    static let explanation = String(
        localized: "The Average is the mean of the running totals of up to three complete earlier periods of this length, counting from the first period with anything in it."
    )
}
