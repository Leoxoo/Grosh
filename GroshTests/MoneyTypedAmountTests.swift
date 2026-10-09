import Foundation
import Testing
@testable import Grosh

struct MoneyTypedAmountTests {
    private static let unitedStates = Locale(identifier: "en_US")
    private static let germany = Locale(identifier: "de_DE")

    @Test(arguments: [
        ("1250", 1_250_00),
        ("12.76", 12_76),
        ("1,250.5", 1_250_50),
        ("$1,250.50", 1_250_50),
        (" 40 ", 40_00),
        ("-40", -40_00),
        ("-$40.10", -40_10),
        ("2.005", 2_01),
    ])
    func readsAnAmountTypedTheUSWay(text: String, expectedCents: Int) {
        #expect(Money(typedAmount: text, locale: Self.unitedStates) == Money(cents: expectedCents))
    }

    @Test func readsAnAmountTypedWithTheUsersOwnSeparators() {
        #expect(Money(typedAmount: "1.250,50", locale: Self.germany) == Money(cents: 1_250_50))
    }

    @Test(arguments: ["", "  ", "abc", "12abc", "1-2", "$"])
    func rejectsTextThatIsNotAnAmount(text: String) {
        #expect(Money(typedAmount: text, locale: Self.unitedStates) == nil)
    }
}
