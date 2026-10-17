import SwiftData
import SwiftUI

/// A screen the Report pushes. Opened from the Report, a details screen shares the Report's wallet selection, time range
/// and period. Opened from a Step's row, it shows that Step's span alone: its own period, a strip of one tab, and the
/// wallet selection it was opened with.
enum ReportScreen: Hashable {
    /// Which details screen.
    enum Details: Hashable {
        case netIncome
    }

    case details(Details)
    case step(Details, span: DayRange, walletSelection: WalletSelection)
}

/// The screen a ``ReportScreen`` names. It is pushed onto the Report's stack, so the details it opens can push more.
struct ReportDestination: View {
    let screen: ReportScreen
    /// The Report's selection, which a details screen opened from the Report shares.
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period

    var body: some View {
        switch screen {
        case .details(let details):
            DetailsScreen(details: details, walletSelection: $walletSelection, timeRange: $timeRange, period: $period)
        case .step(let details, let span, let selection):
            StepSpanScreen(details: details, span: span, walletSelection: selection)
        }
    }
}

/// A details screen for one Step's span, owning its own wallet selection, time range and period, all seeded from the span.
private struct StepSpanScreen: View {
    let details: ReportScreen.Details
    @State private var walletSelection: WalletSelection
    @State private var timeRange: TimeRange
    @State private var period: Period

    init(details: ReportScreen.Details, span: DayRange, walletSelection: WalletSelection) {
        self.details = details
        _walletSelection = State(initialValue: walletSelection)
        _timeRange = State(initialValue: .custom(span))
        _period = State(initialValue: .custom(span))
    }

    var body: some View {
        DetailsScreen(details: details, walletSelection: $walletSelection, timeRange: $timeRange, period: $period)
    }
}

/// The details screen for `details`, on the wallet selection, time range and period it is given.
private struct DetailsScreen: View {
    let details: ReportScreen.Details
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period

    var body: some View {
        switch details {
        case .netIncome:
            NetIncomeDetailsView(walletSelection: $walletSelection, timeRange: $timeRange, period: $period)
        }
    }
}
