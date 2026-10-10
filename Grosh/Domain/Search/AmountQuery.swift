/// A number typed into search, read as an amount. It finds every amount that begins with it, digit for digit
/// from the dollars: `973` finds $973.17 and $973.00, `973.1` finds $973.10 to $973.19, `973.17` finds only
/// $973.17. The sign is ignored, since amounts are entered positive.
nonisolated struct AmountQuery: Equatable {
    /// The typed amount in cents.
    let cents: Int
    /// How many digits of cents were typed: 0, 1 or 2.
    let centDigits: Int

    /// Reads `text` as an amount, or returns `nil` when it isn't one. A currency symbol, a sign and spaces are
    /// ignored. The last `.` or `,` is the decimal point when one or two digits follow it (or none, as while
    /// typing `973.`); every other one groups thousands, so `1,250` and `973,17` both read as expected.
    init?(_ text: String) {
        var plain = ""
        for character in text {
            if character.isASCII, character.isNumber || character == "." || character == "," {
                plain.append(character)
            } else if character == "-" || character == "\u{2212}" || character.isWhitespace || character.isCurrencySymbol {
                continue
            } else {
                return nil
            }
        }
        var dollars = plain
        var centText = ""
        if let point = plain.lastIndex(where: { $0 == "." || $0 == "," }) {
            let after = plain[plain.index(after: point)...]
            if after.count <= 2 {
                dollars = String(plain[..<point])
                centText = String(after)
            }
        }
        dollars.removeAll { $0 == "." || $0 == "," }
        guard !dollars.isEmpty, let whole = Int(dollars), centText.allSatisfy(\.isNumber) else { return nil }
        centDigits = centText.count
        cents = whole * 100 + (Int(centText) ?? 0) * (centDigits == 1 ? 10 : 1)
    }

    /// Whether `amount` begins with the typed digits.
    func matches(_ amount: Money) -> Bool {
        let unit = [100, 10, 1][centDigits]
        return abs(amount.cents) / unit == cents / unit
    }
}

private extension Character {
    nonisolated var isCurrencySymbol: Bool {
        unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol }
    }
}
