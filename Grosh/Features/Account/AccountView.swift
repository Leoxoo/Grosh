import SwiftUI

/// The Account tab: Wallets, Categories, Cards, Debts & Loans, Import, Export, Currency, Recurring transactions.
struct AccountView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecurringTransactionsRow()
                }
            }
            .navigationTitle("Account")
        }
    }
}

#Preview {
    AccountView()
}
