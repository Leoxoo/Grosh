import Foundation

/// An amount of money in integer cents. Money never passes through `Double`.
nonisolated struct Money: Hashable, Sendable {
    var cents: Int

    init(cents: Int) {
        self.cents = cents
    }

    /// Reads keypad-style digits as cents: `1276` is $12.76 and `1200` is $12.00.
    init?(centsFirstDigits digits: String) {
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let cents = Int(digits) else { return nil }
        self.cents = cents
    }

    /// Formats as currency, e.g. `$10,000.00` or `−$0.81` (with U+2212, not a hyphen).
    func formatted(currencyCode: String = "USD", locale: Locale = .current) -> String {
        let units = Decimal(cents.magnitude) / 100
        let text = units.formatted(.currency(code: currencyCode).locale(locale))
        return cents < 0 ? "\u{2212}" + text : text
    }
}
