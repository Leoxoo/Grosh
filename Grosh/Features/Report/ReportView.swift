import SwiftData
import SwiftUI

/// The Report, opened full-screen from Home's Month graph: for the Wallet selector's choice and a period, its opening and
/// ending balances, its Net income and its Category report. It starts on the Total, This month's time range, and the
/// period Home's strip was showing. Its period never reaches past today.
struct ReportView: View {
    @Query(Transaction.notDeleted) private var transactions: [Transaction]
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
        OtherIncomeReader { otherIncome in
            content(otherIncome: otherIncome)
        }
        .onAppear { Signpost.opening("Open Report") }
    }

    /// The Report, with Other Income read once for everything it counts.
    @ViewBuilder
    private func content(otherIncome: Category) -> some View {
        let selected = transactions.filter(walletSelection.includes)
        let counted = transactions.counted(in: walletSelection, during: period, today: today, otherIncome: otherIncome)
        let summary = PeriodSummary(of: selected, in: period, today: today)
        NavigationStack(path: $path) {
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
                    NetIncomeCard(totals: PeriodTotals(of: counted))
                }

                Section {
                    CategoryReportCard(
                        income: CategoryBreakdown(side: .income, of: counted),
                        spent: CategoryBreakdown(side: .spent, of: counted),
                        onOpen: { path.append(ReportScreen.details(.side($0))) }
                    )
                }
            }
            .roundedSectionsListStyle()
            .reportPeriodControls(
                walletSelection: $walletSelection, timeRange: $timeRange, period: $period, transactions: transactions
            )
            .navigationTitle("Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: ReportScreen.self) { screen in
                ReportDestination(screen: screen, walletSelection: $walletSelection, timeRange: $timeRange, period: $period)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
