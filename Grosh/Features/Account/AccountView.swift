import SwiftData
import SwiftUI

/// The Account tab: Wallets, Categories, Cards, Debts & Loans, Import, Export, Currency, Recurring transactions.
struct AccountView: View {
    @AppStorage(CurrencyPickerView.currencyCodeKey) private var currencyCode = Money.defaultCurrencyCode

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        WalletListView()
                    } label: {
                        Label("Wallets", systemImage: "wallet.bifold")
                    }
                    NavigationLink {
                        CategoryListView()
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    NavigationLink {
                        CurrencyPickerView()
                    } label: {
                        LabeledContent {
                            Text(currencyCode)
                        } label: {
                            Label("Currency", systemImage: "dollarsign.circle")
                        }
                    }
                }

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
        .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
