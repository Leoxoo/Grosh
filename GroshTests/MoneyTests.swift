import Foundation
import Testing
@testable import Grosh

struct MoneyTests {
    let enUS = Locale(identifier: "en_US")

    @Test func centsFirstDigitsAreReadAsCents() {
        #expect(Money(centsFirstDigits: "1276")?.formatted(locale: enUS) == "$12.76")
    }

    @Test func doubleZeroKeyAddsWholeDollars() {
        #expect(Money(centsFirstDigits: "12" + "00")?.formatted(locale: enUS) == "$12.00")
    }

    @Test(arguments: ["", "12a", "-12", "+12", "1.5", " 12"])
    func centsFirstEntryAcceptsOnlyDigits(_ input: String) {
        #expect(Money(centsFirstDigits: input) == nil)
    }

    @Test func thousandsAreGrouped() {
        #expect(Money(cents: 1_000_000).formatted(locale: enUS) == "$10,000.00")
    }

    @Test func negativeAmountsUseTheMinusSign() {
        #expect(Money(cents: -81).formatted(locale: enUS) == "\u{2212}$0.81")
    }
}
