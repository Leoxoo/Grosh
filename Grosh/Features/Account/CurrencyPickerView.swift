import SwiftUI

/// Account → Currency. Only USD is offered for now; each wallet already stores its own currency code.
struct CurrencyPickerView: View {
    static let currencyCodeKey = "currencyCode"
    static let offeredCurrencyCodes = [Money.defaultCurrencyCode]

    @AppStorage(Self.currencyCodeKey) private var currencyCode = Money.defaultCurrencyCode

    var body: some View {
        Form {
            Picker("Currency", selection: $currencyCode) {
                ForEach(Self.offeredCurrencyCodes, id: \.self) { code in
                    Text(Locale.current.localizedString(forCurrencyCode: code).map { "\($0) (\(code))" } ?? code)
                        .tag(code)
                }
            }
            .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .navigationTitle("Currency")
    }
}
