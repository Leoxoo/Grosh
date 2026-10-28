import SwiftData
import SwiftUI

/// The app's top level: a tab bar on iPhone, a sidebar on iPad and Mac.
struct RootView: View {
    var body: some View {
        TabView {
            Tab(Strings.Screens.home, systemImage: "house") {
                HomeView()
            }
            Tab(Strings.Common.transactions, systemImage: "wallet.bifold") {
                TransactionsView()
            }
            Tab(Strings.Screens.budgets, systemImage: "chart.pie") {
                BudgetsView()
            }
            Tab(Strings.Screens.account, systemImage: "person.crop.circle") {
                AccountView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .presentsAddTransaction()
        .syncsDebtReminders()
        .syncsEstimateReminders()
        #if os(iOS)
        // iPad opens on the sidebar too, not the floating tab bar; iPhone keeps its tab bar.
        .defaultAdaptableTabBarPlacement(.sidebar)
        #endif
    }
}

#Preview {
    RootView()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
