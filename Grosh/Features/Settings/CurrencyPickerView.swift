import SwiftUI

/// Settings → Currency: the currency a new wallet starts in. Only USD is offered for now; each wallet stores its own.
struct CurrencyPickerView: View {
    static let offeredCurrencyCodes = [Money.defaultCurrencyCode]

    @AppStorage(AppSettings.currencyCodeKey) private var currencyCode = AppSettings.currencyCodeDefault

    var body: some View {
        Form {
            Picker(Strings.Screens.currency, selection: $currencyCode) {
                ForEach(Self.offeredCurrencyCodes, id: \.self) { code in
                    Text(Locale.current.localizedString(forCurrencyCode: code).map { "\($0) (\(code))" } ?? code)
                        .tag(code)
                }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .navigationTitle(Strings.Screens.currency)
    }
}
