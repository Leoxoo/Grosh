import SwiftUI

/// The transactions a Report row opens, by day newest first under their total: those of a Net income or Trend row's
/// Step, or of a Breakdown row's parent category. Tapping one opens its detail. There is no breakdown: this is the list.
struct ReportTransactionsView: View {
    let screen: Screen
    let days: DayRange
    let walletSelection: WalletSelection

    /// Which list it is.
    enum Screen {
        /// A Step's: what counts toward `side`, or toward both sides with Net income for `nil`. `title` names the Step.
        case step(side: SpentOrIncome?, title: String)
        /// A parent category's, its subcategories included, toward `side`.
        case category(SpentOrIncome, Category)
    }

    var body: some View {
        CountedHistoryReader(selection: walletSelection) { history in
            content(listed(in: history))
        }
    }

    private func listed(in history: CountedHistory) -> ReportTransactions {
        switch screen {
        case .step(let side, _): ReportTransactions(step: side, on: days, in: history)
        case .category(let side, let parent): ReportTransactions(category: parent, side: side, on: days, in: history)
        }
    }

    @ViewBuilder
    private func content(_ listed: ReportTransactions) -> some View {
        List {
            Section {
                header(total: listed.total)
            }

            if listed.transactions.isEmpty {
                Section {
                    ContentUnavailableView(Strings.Common.noTransactions, systemImage: "tray", description: emptyText)
                }
            }

            TransactionDaySections(transactions: listed.transactions) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .roundedSectionsListStyle()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The list's total, named for what it adds up: a side or Net income, or the category with its icon.
    @ViewBuilder
    private func header(total: Money) -> some View {
        switch screen {
        case .step(let side, _):
            HStack {
                Text(side?.title ?? String(localized: Strings.Screens.netIncome))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(total.formatted())
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(side?.color ?? total.tint)
            }
        case .category(let side, let category):
            HStack(spacing: 8) {
                CategoryIcon(category: category, size: 28)
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text(total.formatted())
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(side.color)
            }
        }
    }

    private var emptyText: Text {
        switch screen {
        case .step: Text(Strings.Common.nothingRecordedInPeriod)
        case .category: Text(Strings.Report.nothingInCategory)
        }
    }

    private var title: String {
        switch screen {
        case .step(_, let title): title
        case .category(_, let category): category.name
        }
    }
}
