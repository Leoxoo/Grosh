import SwiftData
import SwiftUI

/// A screen the Report pushes: a details screen, the transactions of a Net income or Trend row's Step, or one parent
/// category's transactions. A details screen opened from the Report shares its wallet selection, time range and period.
enum ReportScreen: Hashable {
    /// Which details screen.
    enum Details: Hashable {
        case netIncome
        case side(SpentOrIncome)
    }

    case details(Details)
    /// The transactions that count in a Step's days: toward `side`, or toward both sides for Net income.
    case stepTransactions(side: SpentOrIncome?, title: String, days: DayRange, walletSelection: WalletSelection)
    /// One parent category of a side, listing its transactions over the days the screen it was opened from showed.
    case category(SpentOrIncome, Category, days: DayRange, walletSelection: WalletSelection)
}

/// The screen a ``ReportScreen`` names. It is pushed onto the Report's stack, so the screens it opens can push more.
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
        case .stepTransactions(let side, let title, let days, let selection):
            StepTransactionsView(side: side, title: title, days: days, walletSelection: selection)
        case .category(let side, let category, let days, let selection):
            CategoryTransactionsView(side: side, category: category, days: days, walletSelection: selection)
        }
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
        case .side(let side):
            SideDetailsView(side: side, walletSelection: $walletSelection, timeRange: $timeRange, period: $period)
        }
    }
}
