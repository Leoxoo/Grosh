import SwiftData
import SwiftUI

/// The Report, opened full-screen from Home's Month graph: for the Wallet selector's choice and a period, its opening and
/// ending balances and its Net income. It starts on the Total, This month's time range, and the period Home's strip was
/// showing. Its period never reaches past today.
struct ReportView: View {
    @Query(Transaction.notDeleted) private var transactions: [Transaction]
    @State private var walletSelection = WalletSelection.total
    /// How long each period of the strip is, chosen with the calendar button.
    @State private var timeRange = TimeRange.month
    @State private var period: Period
    @State private var isPickingCustomRange = false
    @Environment(\.dismiss) private var dismiss

    /// The Report opens on `period`, the period Home's strip was showing.
    init(startingOn period: Period) {
        _period = State(initialValue: period)
    }

    private var today: CalendarDay { .today }

    /// The Current period: the period of the time range that holds today.
    private var currentPeriod: Period {
        timeRange.period(containing: today)
    }

    /// The periods the strip offers for `selection`: back to its first transaction, never Future.
    private func strip(for selection: WalletSelection) -> [Period] {
        let selected = transactions.filter(selection.includes)
        return timeRange.periods(from: selected.firstDay, today: today).filter { $0 != .future }
    }

    var body: some View {
        let today = today
        let selected = transactions.filter(walletSelection.includes)
        let totals = PeriodTotals(of: transactions, in: walletSelection, period: period, today: today)
        let summary = PeriodSummary(of: selected, in: period, today: today)
        NavigationStack {
            List {
                Section {
                    LabeledContent("Opening balance") {
                        Text(summary.openingBalance.formatted()).monospacedDigit()
                    }
                    LabeledContent("Ending balance") {
                        Text(summary.endingBalance.formatted()).monospacedDigit()
                    }
                }

                Section {
                    NetIncomeCard(totals: totals)
                }
            }
            .roundedSectionsListStyle()
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 4) {
                    WalletSelector(selection: $walletSelection, today: today)
                    PeriodStrip(periods: strip(for: walletSelection), selection: $period, current: currentPeriod, today: today)
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
            .onChange(of: walletSelection) {
                // A wallet with a shorter history may not reach back to the period being shown.
                period.showCurrentPeriod(currentPeriod, unlessOfferedBy: strip(for: walletSelection))
            }
            .onChange(of: timeRange) {
                // Unlike a wallet change, a new time range always starts on the Current period.
                period = currentPeriod
            }
            .customRangeEditor($timeRange, isPresented: $isPickingCustomRange, latest: today)
            .navigationTitle("Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
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
}

extension View {
    /// Presents the Report: full-screen on iPhone and iPad, and as a sheet on Mac, which has no full-screen cover.
    func reportPresentation(isPresented: Binding<Bool>, content: @escaping () -> some View) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}
