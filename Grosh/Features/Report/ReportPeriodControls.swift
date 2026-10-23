import SwiftData
import SwiftUI

extension View {
    /// The period controls every Report screen shares: the period strip, under the Wallet selector where it is shown, and
    /// the calendar button in the toolbar that picks the Time Range. See ``ReportPeriodControls``.
    func reportPeriodControls(
        walletSelection: Binding<WalletSelection>, timeRange: Binding<TimeRange>, period: Binding<Period>,
        transactions: [Transaction], showsWalletSelector: Bool = true
    ) -> some View {
        modifier(
            ReportPeriodControls(
                walletSelection: walletSelection, timeRange: timeRange, period: period, transactions: transactions,
                showsWalletSelector: showsWalletSelector
            )
        )
    }
}

/// The period controls of a Report screen, which the Report and each details screen share. The strip never offers Future,
/// and its custom range can't reach past today. A new wallet selection moves the period to the Current period when the
/// strip no longer offers it, and a new time range always starts on the Current period, as on the Transactions tab.
struct ReportPeriodControls: ViewModifier {
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period
    /// Every transaction, which the strip starts from the first one of the selected wallets.
    let transactions: [Transaction]
    /// Whether the Wallet selector sits above the strip. A details screen follows the Report's selection without one.
    let showsWalletSelector: Bool

    @Environment(\.today) private var today
    @State private var isPickingCustomRange = false

    /// The Current period: the period of the time range that holds today.
    private var currentPeriod: Period {
        timeRange.period(containing: today)
    }

    /// The periods the strip offers for `selection`: back to its first transaction, never Future.
    private func strip(for selection: WalletSelection) -> [Period] {
        let selected = transactions.filter { selection.includes($0) }
        return timeRange.periods(from: selected.firstDay, today: today).filter { $0 != .future }
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 4) {
                    if showsWalletSelector {
                        WalletSelector(selection: $walletSelection, today: today)
                    }
                    PeriodStrip(
                        periods: strip(for: walletSelection), selection: $period, current: currentPeriod, today: today
                    )
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onChange(of: walletSelection) {
                // A wallet with a shorter history may not reach back to the period being shown.
                period.showCurrentPeriod(currentPeriod, unlessOfferedBy: strip(for: walletSelection))
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
                        Label("Time Range", systemImage: "calendar")
                    }
                }
            }
    }
}
