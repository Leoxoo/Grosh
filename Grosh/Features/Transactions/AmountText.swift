import SwiftUI

extension Money {
    /// Muted green for money coming in, muted red for money going out; zero stays plain text.
    var tint: Color {
        cents > 0 ? Color("AmountGreen") : cents < 0 ? Color("AmountRed") : .primary
    }

    /// The amount with its sign always shown: "+$12.76", "−$4.50". Zero has no sign.
    func signedFormatted(locale: Locale = .current) -> String {
        guard cents != 0 else { return formatted(locale: locale) }
        return decimalValue.formatted(.currency(code: currencyCode).sign(strategy: .always()).locale(locale))
    }
}

/// An amount in its color: green when it adds to a balance, red when it takes from it.
struct AmountText: View {
    let amount: Money
    /// Whether to show "+" on amounts that add, as day totals and differences do.
    var showsPlusSign = false
    /// Whether to color the amount. Totals are plain text, and their sign shows which way they go.
    var showsColor = true

    var body: some View {
        Text(showsPlusSign ? amount.signedFormatted() : amount.formatted())
            .monospacedDigit()
            .foregroundStyle(showsColor ? amount.tint : .primary)
    }
}
