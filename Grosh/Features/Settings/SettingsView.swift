import SwiftUI

/// Account → Settings: the app's preferences, one section each. It is shown on every device and Currency is always its
/// first section, so it is never empty; a section only some devices offer sits below it.
struct SettingsView: View {
    @AppStorage(CurrencyPickerView.currencyCodeKey) private var currencyCode = Money.defaultCurrencyCode

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
