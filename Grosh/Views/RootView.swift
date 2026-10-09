import SwiftUI

/// The app's top level: a tab bar on iPhone, a sidebar on iPad and Mac.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Transactions", systemImage: "wallet.bifold") {
                TransactionsView()
            }
            Tab("Budgets", systemImage: "chart.pie") {
                BudgetsView()
            }
            Tab("Account", systemImage: "person.crop.circle") {
                AccountView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .presentsAddTransaction()
        #if os(iOS)
        // iPad opens on the sidebar too, not the floating tab bar; iPhone keeps its tab bar.
        .defaultAdaptableTabBarPlacement(.sidebar)
        #endif
    }
}

#Preview {
    RootView()
}
