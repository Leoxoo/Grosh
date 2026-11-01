import Foundation
import Testing
@testable import Grosh

/// The Keypad: amounts are typed the way they're written, with the decimal separator typed by hand.
@Suite(.namedInTheLog)
struct AmountEntryTests {
    private let usEnglish = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    /// Types `text` on a fresh entry, one key per character: digits, `.`, `+ - * /`, `=`, `<` for backspace and `C`.
    private func entry(_ text: String, kind: AmountEntry.Kind = .signedByCategory) -> AmountEntry {
        var entry = AmountEntry(kind: kind)
        entry.type(text)
        return entry
    }

    /// Types `lhs`, the operation, `rhs`, then `=`.
    private func calculate(_ lhs: String, _ operation: CalculatorOperation, _ rhs: String) -> AmountEntry {
        var result = entry(lhs)
        result.press(.operation(operation))
        result.type(rhs + "=")
        return result
    }

    // MARK: Typing as written

    @Test(arguments: [
        ("6", 600, "6"), ("6.", 600, "6."), ("6.3", 630, "6.3"), ("6.35", 635, "6.35"), ("1234.5", 1234_50, "1,234.5"),
        (".5", 50, "0.5"), ("0", 0, "0"), ("007", 700, "7"),
    ])
    func amountsAreTypedAsWritten(typed: String, cents: Int, shown: String) {
        let typed = entry(typed)

        #expect(typed.cents == cents)
        #expect(typed.text(locale: usEnglish) == shown)
    }

    @Test func aFreshEntryShowsZeroAndIsEmpty() {
        #expect(AmountEntry().cents == 0)
        #expect(AmountEntry().text(locale: usEnglish) == "0")
        #expect(AmountEntry().isEmpty)
        #expect(!entry("0").isEmpty)
    }

    @Test func aSeparatorTypedFirstGivesZeroPoint() {
        #expect(entry(".").text(locale: usEnglish) == "0.")
    }

    @Test func aSecondSeparatorIsIgnored() {
        var typed = entry("6.3")

        let taken = typed.press(.decimalSeparator)
        #expect(taken)
        #expect(typed.text(locale: usEnglish) == "6.3")
        #expect(typed.cents == 630)
    }

    @Test func aThirdDigitAfterTheSeparatorIsRefused() {
        var typed = entry("6.35")

        let taken = typed.press(.digit(7))
        #expect(!taken)
        #expect(typed.cents == 635)
        #expect(typed.text(locale: usEnglish) == "6.35")
    }

    @Test func digitsPastTheLargestAmountAreRefused() {
        var typed = entry("999999999")

        let taken = typed.press(.digit(9))
        #expect(!taken)
        typed.type(".99")
        #expect(typed.cents == 99_999_999_999)
        #expect(typed.text(locale: usEnglish) == "999,999,999.99")
    }

    @Test func theRegionsSeparatorAndGroupingAreShown() {
        #expect(entry("1234.5").text(locale: german) == "1.234,5")
        #expect(entry("6.").text(locale: german) == "6,")
    }

    @Test func theFieldShowsTheAmountAsTypedAsMoney() {
        #expect(entry("1234.5").amountText(currencyCode: "USD", locale: usEnglish) == "$1,234.5")
        #expect(entry("6.").amountText(currencyCode: "USD", locale: usEnglish) == "$6.")
        #expect(AmountEntry().amountText(currencyCode: "USD", locale: usEnglish) == "$0")
        #expect(entry("6.3").amountText(currencyCode: "EUR", locale: german) == "6,3\u{00A0}€")
    }

    @Test func whileCalculatingTheFieldShowsWhatItComesToUnpadded() {
        let typed = entry("12+3.5")

        #expect(typed.amountText(currencyCode: "USD", locale: usEnglish) == "$15.5")
    }

    // MARK: Deleting and clearing

    @Test func backspaceDeletesOneCharacter() {
        var typed = entry("12.5")

        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "12.")
        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "12")
        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "1")
        typed.press(.backspace)
        #expect(typed.isEmpty)
        #expect(typed.text(locale: usEnglish) == "0")
    }

    @Test func clearEmptiesTheWholeEntry() {
        let typed = entry("12+3.5C")

        #expect(typed.isEmpty)
        #expect(!typed.isCalculation)
        #expect(typed.cents == 0)
    }

    // MARK: An existing amount

    @Test(arguments: [(1200, "12"), (1250, "12.5"), (1205, "12.05"), (5, "0.05")])
    func anExistingAmountOpensUnpadded(cents: Int, shown: String) {
        let existing = AmountEntry(cents: cents)

        #expect(existing.cents == cents)
        #expect(existing.text(locale: usEnglish) == shown)
    }

    @Test func anExistingZeroIsEmpty() {
        #expect(AmountEntry(cents: 0).isEmpty)
    }

    @Test func theFirstDigitReplacesAnExistingAmount() {
        var existing = AmountEntry(cents: 1250)
        existing.press(.digit(5))

        #expect(existing.cents == 500)
    }

    @Test func backspaceTrimsAnExistingAmount() {
        var existing = AmountEntry(cents: 1250)
        existing.press(.backspace)

        #expect(existing.text(locale: usEnglish) == "12.")
        existing.press(.digit(7))
        #expect(existing.cents == 1270)
    }

    @Test func anOperationCarriesOnFromAnExistingAmount() {
        var existing = AmountEntry(cents: 1250)
        existing.type("+1=")

        #expect(existing.cents == 1350)
    }

    // MARK: Calculator

    @Test func theDisplayShowsTheExpressionAsTyped() {
        #expect(entry("1+3.5").text(locale: usEnglish) == "1 + 3.5")
        #expect(entry("1000*3.").text(locale: usEnglish) == "1,000 × 3.")
    }

    @Test func anEntryIsACalculationOnlyWhileItHasAnOperation() {
        var typed = entry("12")
        #expect(!typed.isCalculation)

        typed.press(.operation(.add))
        #expect(typed.isCalculation)

        typed.press(.equals)
        #expect(!typed.isCalculation)
    }

    @Test func equalsShowsTheResultUnpadded() {
        let added = entry("12+3.5=")

        #expect(added.cents == 15_50)
        #expect(added.text(locale: usEnglish) == "15.5")
    }

    @Test func multiplyingTreatsBothNumbersAsAmounts() {
        #expect(calculate("12", .multiply, "3").cents == 36_00)
    }

    @Test func multiplyingRoundsToTheNearestCent() {
        #expect(calculate("1.25", .multiply, ".5").cents == 63)
    }

    @Test(arguments: [("10", "3", 333), ("20", "3", 667)])
    func dividingRoundsToTheNearestCent(lhs: String, rhs: String, expected: Int) {
        #expect(calculate(lhs, .divide, rhs).cents == expected)
    }

    @Test func multiplyingAndDividingComeBeforeAddingAndSubtracting() {
        #expect(entry("10+2*3=").cents == 16_00)
    }

    @Test func dividingByZeroIsAnErrorWithNoAmount() {
        let result = calculate("10", .divide, "0")

        #expect(result.cents == nil)
        #expect(result.text(locale: usEnglish) == "Error")
        #expect(result.amountText(currencyCode: "USD", locale: usEnglish) == "Error")
    }

    @Test func aDigitAfterAnErrorStartsOver() {
        var result = calculate("10", .divide, "0")
        result.press(.digit(5))

        #expect(result.cents == 500)
        #expect(result.text(locale: usEnglish) == "5")
    }

    @Test func aResultTooLargeToHoldIsAnError() {
        #expect(calculate("999999999", .multiply, "999999999").cents == nil)
    }

    @Test func anOperationWithNothingAfterItIsLeftOutOfTheAmount() {
        let typed = entry("12+")

        #expect(typed.cents == 12_00)
        #expect(typed.text(locale: usEnglish) == "12 +")
    }

    @Test func aSecondOperationKeyReplacesTheFirst() {
        #expect(entry("12+*2=").cents == 24_00)
    }

    @Test func backspaceRemovesTheNumberAfterAnOperationThenTheOperation() {
        var typed = entry("12+5")

        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "12 +")

        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "12")
        #expect(typed.cents == 12_00)
    }

    @Test func aDigitAfterEqualsStartsANewAmount() {
        var result = calculate("12", .add, "3")
        result.press(.digit(5))

        #expect(result.cents == 500)
    }

    @Test func anOperationAfterEqualsContinuesFromTheResult() {
        var result = calculate("12", .add, "3")
        result.type("+1=")

        #expect(result.cents == 16_00)
    }

    @Test func workingOutLeavesOneNumber() {
        var typed = entry("12+3")

        let taken = typed.workOut()
        #expect(taken)
        #expect(!typed.isCalculation)
        #expect(typed.cents == 15_00)
    }

    // MARK: The sign, set by the category

    @Test func aLeadingMinusIsRefusedWhereTheCategorySetsTheSign() {
        var typed = AmountEntry()

        let taken = typed.press(.operation(.subtract))
        #expect(!taken)
        #expect(typed.isEmpty)
    }

    @Test func aCalculationBelowZeroIsAnErrorWhereTheCategorySetsTheSign() {
        let typed = entry("5-12")

        #expect(typed.cents == nil)
        #expect(typed.amountText(currencyCode: "USD", locale: usEnglish) == "Error")
    }

    @Test func equalsRefusesACalculationBelowZeroWhereTheCategorySetsTheSign() {
        var typed = entry("5-12")

        let taken = typed.press(.equals)
        #expect(!taken)
        #expect(typed.isCalculation)
        #expect(typed.text(locale: usEnglish) == "5 − 12")

        typed.press(.backspace)
        typed.press(.backspace)
        typed.press(.digit(2))
        let taken2 = typed.press(.equals)
        #expect(taken2)
        #expect(typed.cents == 3_00)
    }

    // MARK: The sign of a balance

    @Test func aLeadingMinusMakesABalanceNegative() {
        let typed = entry("-12.5", kind: .balance)

        #expect(typed.cents == -12_50)
        #expect(typed.text(locale: usEnglish) == "-12.5")
        #expect(typed.amountText(currencyCode: "USD", locale: usEnglish) == "-$12.5")
    }

    @Test func aMinusAloneIsShownAndComesToZero() {
        let typed = entry("-", kind: .balance)

        #expect(typed.cents == 0)
        #expect(typed.text(locale: usEnglish) == "-")
        #expect(!typed.isEmpty)
    }

    @Test func backspaceDeletesTheSignLast() {
        var typed = entry("-5", kind: .balance)

        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "-")
        typed.press(.backspace)
        #expect(typed.isEmpty)
    }

    @Test func anOperationAfterAMinusAloneIsRefused() {
        var typed = entry("-", kind: .balance)

        let taken = typed.press(.operation(.add))
        #expect(!taken)
        let taken2 = typed.press(.operation(.subtract))
        #expect(!taken2)
    }

    @Test func aBalanceCalculationMayComeOutBelowZero() {
        let result = entry("5-12=", kind: .balance)

        #expect(result.cents == -7_00)
        #expect(result.text(locale: usEnglish) == "-7")
    }

    @Test func aMinusAfterAnExistingBalanceSubtracts() {
        var existing = AmountEntry(cents: 100_00, kind: .balance)
        existing.type("-30=")

        #expect(existing.cents == 70_00)
    }

    @Test func anExistingNegativeBalanceOpensWithItsSign() {
        let existing = AmountEntry(cents: -12_50, kind: .balance)

        #expect(existing.cents == -12_50)
        #expect(existing.text(locale: usEnglish) == "-12.5")
    }

    @Test func clearKeepsTheKind() {
        var typed = entry("12C", kind: .balance)

        let taken = typed.press(.operation(.subtract))
        #expect(taken)
        #expect(typed.kind == .balance)
    }

    // MARK: Typing on a hardware keyboard

    @Test func typingOnAKeyboardIsAsWrittenToo() {
        var typed = AmountEntry()
        for character in "12.76" {
            if let key = KeypadKey(typing: character) { typed.press(key) }
        }

        #expect(typed.cents == 12_76)
    }

    @Test(arguments: [
        (".", KeypadKey.decimalSeparator), (",", .decimalSeparator),
        ("+", .operation(.add)), ("-", .operation(.subtract)), ("−", .operation(.subtract)),
        ("*", .operation(.multiply)), ("x", .operation(.multiply)), ("×", .operation(.multiply)),
        ("/", .operation(.divide)), ("÷", .operation(.divide)), ("=", .equals),
        ("\u{7F}", .backspace), ("\u{8}", .backspace), ("c", .allClear), ("C", .allClear),
    ] as [(Character, KeypadKey)])
    func keyboardKeysMatchTheKeypad(character: Character, key: KeypadKey) {
        #expect(KeypadKey(typing: character) == key)
    }

    @Test(arguments: ["a", " ", "%"] as [Character])
    func otherKeyboardKeysAreIgnored(character: Character) {
        #expect(KeypadKey(typing: character) == nil)
    }
}

private extension AmountEntry {
    /// Types each character as its key: digits, `.`, `+ - * /`, `=`, `<` for backspace and `C` for clear.
    mutating func type(_ text: String) {
        for character in text {
            let key = character == "<" ? .backspace : KeypadKey(typing: character)
            if let key { press(key) }
        }
    }
}
