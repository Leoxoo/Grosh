import SwiftUI

/// The Budgets tab. Budgets are out of scope for v1, so it shows a coming-soon state.
struct BudgetsView: View {
    var body: some View {
        NavigationStack {
            ComingSoonScreen(placeholder: .budgets)
        }
    }
}

#Preview {
    BudgetsView()
}
