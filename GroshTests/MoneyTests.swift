import Foundation
import Testing
@testable import Grosh

struct MoneyTests {
    private let unitedStates = Locale(identifier: "en_US")

    @Test(arguments: [
        (1276, "$12.76"),
        (-81, "-$0.81"),
        (1_000_000, "$10,000.00"),
        (0, "$0.00"),
    ])
    func formatsCentsAsUSD(cents: Int, expected: String) {
        #expect(Money(cents: cents).formatted(locale: unitedStates) == expected)
    }

    @Test(arguments: [
        ("12.76", 1276),
        ("-0.81", -81),
        ("10000", 1_000_000),
        ("-46.9", -4690),
        ("-74.910004", -7491),
        ("2.005", 201),
    ])
    func parsesDecimalStringsRoundedToCents(text: String, expectedCents: Int) {
        #expect(Money(decimalString: text) == Money(cents: expectedCents))
    }

    @Test(arguments: ["", "abc", "12abc", "1,000.00", "--5"])
    func rejectsTextThatIsNotADecimalNumber(text: String) {
        #expect(Money(decimalString: text) == nil)
    }
}
