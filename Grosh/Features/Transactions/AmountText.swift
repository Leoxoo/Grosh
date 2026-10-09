import SwiftUI

extension Money {
    /// Green for money coming in, red for money going out.
    var tint: Color {
        cents > 0 ? .green : cents < 0 ? .red : .primary
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

    var body: some View {
        Text(showsPlusSign ? amount.signedFormatted() : amount.formatted())
            .monospacedDigit()
            .foregroundStyle(amount.tint)
    }
}
