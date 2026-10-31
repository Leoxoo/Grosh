import SwiftData
import SwiftUI

/// The Home tab: the Total, the user's wallets, the Month graph with its Spent and Income tabs, and the coming-soon
/// cards. Its toolbar opens search and the bell of due Loan and Debt reminders.
struct HomeView: View {
    /// Remembers across launches whether the Total is hidden.
    static let isTotalHiddenKey = "home.isTotalHidden"

    @Environment(\.today) private var today

    var body: some View {
        HomeContent(startingMonth: .month(CalendarMonth(today)))
            .onAppear { Signpost.opening("Open Home") }
    }
}

/// The screen behind ``HomeView``, holding the month its Month graph shows from the moment Home opens.
private struct HomeContent: View {
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    /// What the Total and the wallets' balances add up.
    @NotDeletedTransactions private var transactions: [Transaction]
    @AppStorage(HomeView.isTotalHiddenKey) private var isTotalHidden = false
    @Environment(\.today) private var today
    /// The month Home's Month graph shows, which the Report opens on.
    @State private var monthPeriod: Period
    /// Whether the Report is open.
    @State private var isShowingReport = false

    init(startingMonth: Period) {
        _monthPeriod = State(initialValue: startingMonth)
    }

    var body: some View {
        let balances = WalletBalances($transactions, asOf: today)
        NavigationStack {
            List {
                Section {
                    TotalBalanceView(total: balances.total(of: wallets), isHidden: $isTotalHidden)
                }

                Section {
                    if wallets.isEmpty {
                        NavigationLink(Strings.Home.addAWallet) { WalletListView() }
                    }
                    ForEach(wallets) { wallet in
                        WalletRow(wallet: wallet, today: today, balances: balances)
                    }
                } header: {
                    HStack {
                        Text(Strings.Home.myWallets)
                        Spacer()
                        NavigationLink(Strings.Home.seeAll) { WalletListView() }
                            .font(.subheadline)
                            .textCase(nil)
                    }
                }

                HomeMonthGraph(today: today, period: $monthPeriod, isShowingReport: $isShowingReport)

                HomeComingSoonCards()

                RecentTransactionsSection(today: today)
            }
            .navigationTitle(Strings.Screens.home)
            .tabRootTitle(Strings.Screens.home)
            // Presented from the list itself, not from a row of it, so the Report opens on the month the strip shows.
            .reportPresentation(isPresented: $isShowingReport) {
                ReportView(startingOn: monthPeriod)
            }
            .transactionSearchButton()
            .dueRemindersBell()
            .addTransactionButton()
        }
    }
}

/// The Total, with an eye button that hides the amount.
private struct TotalBalanceView: View {
    let total: Money
    @Binding var isHidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(isHidden ? "••••••" : total.formatted())
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .accessibilityLabel(isHidden ? Text(Strings.Common.hidden) : Text(total.formatted()))
                Button {
                    withAnimation { isHidden.toggle() }
                } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isHidden ? Strings.Home.showTotal : Strings.Home.hideTotal)
            }
            Text(Strings.Home.totalBalance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
