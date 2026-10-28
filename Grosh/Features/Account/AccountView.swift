import SwiftData
import SwiftUI

/// The Account tab: Wallets, Categories, Cards, Debts & Loans, Recently Deleted, Import, Export, Settings, Recurring
/// transactions.
struct AccountView: View {
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
                    NavigationLink {
                        CardListView()
                    } label: {
                        Label("Cards", systemImage: "creditcard")
                    }
                    NavigationLink {
                        DebtsLoansView()
                    } label: {
                        Label("Debts & Loans", systemImage: "person.2")
                    }
                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                }

                Section {
                    NavigationLink {
                        ImportFromMoneyLoverView()
                    } label: {
                        Label("Import from MoneyLover", systemImage: "square.and.arrow.down")
                    }
                    NavigationLink {
                        ExportCSVView()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                Section {
                    RecurringTransactionsRow()
                }
            }
            .navigationTitle("Account")
            .tabRootTitle()
        }
    }
}

#Preview {
    AccountView()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
