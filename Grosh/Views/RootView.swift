import SwiftUI

/// The app's top level: a tab bar on iPhone, a sidebar on iPad and Mac.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Transactions", systemImage: "wallet.bifold") {
                PlaceholderScreen(title: "Transactions", systemImage: "wallet.bifold")
            }
            Tab("Budgets", systemImage: "chart.pie") {
                BudgetsView()
            }
            Tab("Account", systemImage: "person.crop.circle") {
                AccountView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        // iPad opens on the sidebar too, not the floating tab bar; iPhone keeps its tab bar.
        .defaultAdaptableTabBarPlacement(.sidebar)
        #endif
    }
}

/// Stands in for a tab until its real screen is built.
private struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming soon"))
                .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
}
