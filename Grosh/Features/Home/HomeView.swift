import SwiftUI

/// The Home tab.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                // Total balance and My Wallets go above the coming-soon cards; Recent transactions below.
                HomeComingSoonCards()
            }
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView()
}
