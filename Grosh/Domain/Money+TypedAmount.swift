import Foundation

extension Money {
    /// Reads an amount the user typed into a text field, such as `1,250.50`, `$40` or `-12.5`, using the
    /// locale's decimal and grouping separators. Rounds to the nearest cent. Returns nil for anything else.
    init?(typedAmount text: String, locale: Locale = .current, currencyCode: String = defaultCurrencyCode) {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        var plain = ""
        for character in text {
            if character.isASCII, character.isNumber {
                plain.append(character)
            } else if String(character) == decimalSeparator {
                plain.append(".")
            } else if character == "-" || character == "\u{2212}" {
                plain.append("-")
            } else if String(character) == groupingSeparator || character.isWhitespace || character.isCurrencySymbol {
                continue
            } else {
                return nil
            }
        }
        self.init(decimalString: plain, currencyCode: currencyCode)
    }
}

private extension Character {
    var isCurrencySymbol: Bool {
        unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol }
    }
}
