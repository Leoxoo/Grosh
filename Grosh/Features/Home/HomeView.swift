import SwiftData
import SwiftUI

/// The Home tab: the Total, the user's wallets, the Month graph with its Spent and Income tabs, and the coming-soon
/// cards. Its toolbar opens search and the bell of due Loan and Debt reminders.
struct HomeView: View {
    /// Remembers across launches whether the Total is hidden.
    static let isTotalHiddenKey = "home.isTotalHidden"

    @Query(Wallet.unarchived) private var wallets: [Wallet]
    /// What the Total and the wallets' balances add up.
    @NotDeletedTransactions private var transactions: [Transaction]
    @AppStorage(Self.isTotalHiddenKey) private var isTotalHidden = false

    private var today: CalendarDay { .today }

    var body: some View {
        let balances = WalletBalances($transactions, asOf: today)
        NavigationStack {
            List {
                Section {
                    TotalBalanceView(total: balances.total(of: wallets), isHidden: $isTotalHidden)
                }

                Section {
                    if wallets.isEmpty {
                        NavigationLink("Add a wallet") { WalletListView() }
                    }
                    ForEach(wallets) { wallet in
                        WalletRow(wallet: wallet, today: today, balances: balances)
                    }
                } header: {
                    HStack {
                        Text("My Wallets")
                        Spacer()
                        NavigationLink("See all") { WalletListView() }
                            .font(.subheadline)
                            .textCase(nil)
                    }
                }

                HomeMonthGraph(today: today)

                HomeComingSoonCards()

                RecentTransactionsSection()
            }
            .navigationTitle("Home")
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
                    .contentTransition(.numericText())
                    .accessibilityLabel(isHidden ? Text("Hidden") : Text(total.formatted()))
                Button {
                    withAnimation { isHidden.toggle() }
                } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isHidden ? "Show Total" : "Hide Total")
            }
            Text("Total balance")
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
