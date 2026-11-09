import SwiftData
import SwiftUI

extension View {
    /// The period controls every Report screen shares: the period strip of `history`, under the Wallet selector where it
    /// is shown, and the calendar button in the toolbar that picks the Time Range. See ``ReportPeriodControls``.
    func reportPeriodControls(
        walletSelection: Binding<WalletSelection>, timeRange: Binding<TimeRange>, period: Binding<Period>,
        history: CountedHistory, showsWalletSelector: Bool = true
    ) -> some View {
        modifier(
            ReportPeriodControls(
                walletSelection: walletSelection, timeRange: timeRange, period: period, history: history,
                showsWalletSelector: showsWalletSelector
            )
        )
    }
}

/// The period controls of a Report screen, which the Report and each details screen share. The strip starts at the
/// period of the first day anything counts for the selected wallets and never offers Future
/// (``CountedHistory/strip(_:today:)``), and its custom range can't reach past today. A new wallet selection moves the
/// period to the Current period when the strip no longer offers it, and a new time range always starts on the Current
/// period, as on the Transactions tab.
struct ReportPeriodControls: ViewModifier {
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period
    /// What counts for `walletSelection`, which the strip starts from.
    let history: CountedHistory
    /// Whether the Wallet selector sits above the strip. A details screen follows the Report's selection without one.
    let showsWalletSelector: Bool

    @Environment(\.today) private var today
    @State private var isPickingCustomRange = false

    /// The Current period: the period of the time range that holds today.
    private var currentPeriod: Period {
        timeRange.period(containing: today)
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 4) {
                    if showsWalletSelector {
                        WalletSelector(selection: $walletSelection, today: today)
                    }
                    PeriodStrip(
                        periods: history.strip(timeRange, today: today), selection: $period, current: currentPeriod,
                        today: today
                    )
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onChange(of: walletSelection) {
                // A wallet with a shorter history may not reach back to the period being shown. The screen has
                // already counted for the new selection by the time this runs.
                period.showCurrentPeriod(currentPeriod, unlessOfferedBy: history.strip(timeRange, today: today))
            }
            .onChange(of: timeRange) {
                period = currentPeriod
            }
            .customRangeEditor($timeRange, isPresented: $isPickingCustomRange, latest: today)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        TimeRangeChoices(timeRange: $timeRange) { isPickingCustomRange = true }
                    } label: {
                        Label(Strings.Common.timeRange, systemImage: "calendar")
                    }
                }
            }
    }
}
