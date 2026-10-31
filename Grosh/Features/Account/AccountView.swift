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
                        Label(Strings.Screens.wallets, systemImage: "wallet.bifold")
                    }
                    NavigationLink {
                        CategoryListView()
                    } label: {
                        Label(Strings.Screens.categories, systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        CardListView()
                    } label: {
                        Label(Strings.Screens.cards, systemImage: "creditcard")
                    }
                    NavigationLink {
                        DebtsLoansView()
                    } label: {
                        Label(Strings.Screens.debtsAndLoans, systemImage: "person.2")
                    }
                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        Label(Strings.Screens.recentlyDeleted, systemImage: "trash")
                    }
                }

                Section {
                    NavigationLink {
                        ImportFromMoneyLoverView()
                    } label: {
                        Label(Strings.Screens.importFromMoneyLover, systemImage: "square.and.arrow.down")
                    }
                    NavigationLink {
                        ExportCSVView()
                    } label: {
                        Label(Strings.Screens.exportCSV, systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(Strings.Screens.settings, systemImage: "gearshape")
                    }
                }

                Section {
                    RecurringTransactionsRow()
                }
            }
            .navigationTitle(Strings.Screens.account)
            .tabRootTitle(Strings.Screens.account)
        }
    }
}

#Preview {
    AccountView()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
