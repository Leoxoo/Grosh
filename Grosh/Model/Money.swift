import Foundation

/// An exact amount of money in minor units (cents). Never stored or computed as a floating-point number.
nonisolated struct Money: Hashable, Sendable {
    /// The only currency offered for now; each wallet stores its own code so more can follow.
    static let defaultCurrencyCode = "USD"

    var cents: Int
    var currencyCode: String = defaultCurrencyCode

    var decimalValue: Decimal { Decimal(cents) / 100 }

    func formatted(locale: Locale = .current) -> String {
        decimalValue.formatted(.currency(code: currencyCode).locale(locale))
    }
}

nonisolated extension Money {
    /// Parses a plain decimal number such as `-74.910004`, rounding half away from zero to the nearest cent.
    /// No grouping separators or currency symbols are accepted.
    init?(decimalString text: String, currencyCode: String = defaultCurrencyCode) {
        guard text.wholeMatch(of: #/-?[0-9]+(\.[0-9]+)?/#) != nil,
              var amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        amount *= 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 0, .plain)
        self.init(cents: NSDecimalNumber(decimal: rounded).intValue, currencyCode: currencyCode)
    }
}

nonisolated extension Money {
    /// The amount as a plain decimal number of exactly two decimals, such as `-74.91` or `1000.00`: what
    /// ``init(decimalString:currencyCode:)`` reads back.
    var decimalString: String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = cents.magnitude
        let hundredths = magnitude % 100
        return "\(sign)\(magnitude / 100).\(hundredths < 10 ? "0" : "")\(hundredths)"
    }
}
