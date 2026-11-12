import SwiftData
import SwiftUI

/// The Report, opened full-screen from Home's Month graph: for the Wallet selector's choice and a period, its opening and
/// ending balances, its Net income and its Category report. It starts on the Total, This month's time range, and the
/// period Home's strip was showing. Its period never reaches past today.
struct ReportView: View {
    @NotDeletedTransactions private var transactions: [Transaction]
    @State private var walletSelection = WalletSelection.total
    /// How long each period of the strip is, chosen with the calendar button.
    @State private var timeRange = TimeRange.month
    @State private var period: Period
    /// The screens pushed onto the Report, such as a side's details opened from a Category report tile.
    @State private var path = NavigationPath()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.today) private var today

    /// The Report opens on `period`, the period Home's strip was showing.
    init(startingOn period: Period) {
        _period = State(initialValue: period)
    }

    var body: some View {
        CountedHistoryReader(selection: walletSelection) { history in
            content(history)
        }
        .onAppear { Signpost.opening("Open Report") }
    }

    @ViewBuilder
    private func content(_ history: CountedHistory) -> some View {
        let counted = history.during(period, today: today)
        let summary = PeriodSummary(of: transactions.filter(walletSelection.includes), in: period, today: today)
        NavigationStack(path: $path) {
            List {
                Section {
                    LabeledContent(Strings.Common.openingBalance) {
                        Text(summary.openingBalance.formatted()).monospacedDigit()
                    }
                    LabeledContent(Strings.Common.endingBalance) {
                        Text(summary.endingBalance.formatted()).monospacedDigit()
                    }
                }

                Section {
                    NetIncomeCard(totals: PeriodTotals(of: counted, currencyCode: history.currencyCode))
                }

                Section {
                    CategoryReportCard(
                        income: CategoryBreakdown(side: .income, of: counted, currencyCode: history.currencyCode),
                        spent: CategoryBreakdown(side: .spent, of: counted, currencyCode: history.currencyCode),
                        onOpen: { path.append(ReportScreen.details(.side($0))) }
                    )
                }
            }
            .roundedSectionsListStyle()
            .reportPeriodControls(
                walletSelection: $walletSelection, timeRange: $timeRange, period: $period, history: history
            )
            .navigationTitle(Strings.Screens.report)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: ReportScreen.self) { screen in
                ReportDestination(screen: screen, walletSelection: $walletSelection, timeRange: $timeRange, period: $period)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.close) { dismiss() }
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
