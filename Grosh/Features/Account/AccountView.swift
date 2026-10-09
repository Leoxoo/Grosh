import SwiftData
import SwiftUI

/// The Account tab: where the user manages wallets, categories, Cards and app settings.
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
            }
            .navigationTitle("Account")
        }
    }
}

#Preview {
    AccountView()
        .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
