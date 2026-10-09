import Foundation
import Testing
@testable import Grosh

/// The cents-first keypad: digits fill the amount from the cents up, like a card terminal.
struct AmountEntryTests {
    private let usEnglish = Locale(identifier: "en_US")

    /// Presses each key in turn on a fresh entry.
    private func entry(_ keys: KeypadKey...) -> AmountEntry {
        entry(keys)
    }

    private func entry(_ keys: [KeypadKey]) -> AmountEntry {
        var entry = AmountEntry()
        for key in keys {
            entry.press(key)
        }
        return entry
    }

    /// The digit keys that type `digits`, e.g. `"1200"` for 12.00.
    private func typing(_ digits: String) -> [KeypadKey] {
        digits.compactMap(\.wholeNumberValue).map(KeypadKey.digit)
    }

    /// Types `lhs`, the operation, `rhs`, then `=`.
    private func calculate(_ lhs: String, _ operation: CalculatorOperation, _ rhs: String) -> AmountEntry {
        entry(typing(lhs) + [.operation(operation)] + typing(rhs) + [.equals])
    }

    @Test func digitsAreEnteredCentsFirst() {
        let typed = entry(.digit(1), .digit(2), .digit(7), .digit(6))

        #expect(typed.cents == 1276)
        #expect(typed.text(locale: usEnglish) == "12.76")
    }

    @Test func doubleZeroAddsTwoZeros() {
        let typed = entry(.digit(1), .digit(2), .doubleZero)

        #expect(typed.cents == 1200)
        #expect(typed.text(locale: usEnglish) == "12.00")
    }

    @Test func aFreshEntryShowsZeroWithTwoDecimals() {
        #expect(AmountEntry().cents == 0)
        #expect(AmountEntry().text(locale: usEnglish) == "0.00")
    }

    @Test func backspaceRemovesTheLastDigit() {
        let typed = entry(.digit(1), .digit(2), .digit(7), .digit(6), .backspace)

        #expect(typed.cents == 127)
        #expect(typed.text(locale: usEnglish) == "1.27")
    }

    @Test func allClearStartsOver() {
        let typed = entry(.digit(1), .digit(2), .allClear)

        #expect(typed.cents == 0)
        #expect(typed.text(locale: usEnglish) == "0.00")
    }

    // MARK: Calculator

    @Test func theDisplayShowsTheExpressionWhileItIsTyped() {
        let typed = entry(.digit(1), .doubleZero, .operation(.add), .digit(3), .digit(5), .digit(0))

        #expect(typed.text(locale: usEnglish) == "1.00 + 3.50")
    }

    @Test func anEntryIsACalculationOnlyWhileItHasAnOperation() {
        var typed = entry(typing("1200"))
        #expect(!typed.isCalculation)

        typed.press(.operation(.add))
        #expect(typed.isCalculation)

        typed.press(.equals)
        #expect(!typed.isCalculation)
    }

    @Test func equalsAddsInCents() {
        let added = entry(.digit(1), .digit(2), .doubleZero, .operation(.add), .digit(3), .digit(5), .digit(0), .equals)

        #expect(added.cents == 1550)
        #expect(added.text(locale: usEnglish) == "15.50")
    }

    @Test func multiplyingTreatsBothNumbersAsAmounts() {
        #expect(calculate("1200", .multiply, "300").cents == 3600)
    }

    @Test func multiplyingRoundsToTheNearestCent() {
        #expect(calculate("125", .multiply, "50").cents == 63)
    }

    @Test(arguments: [("1000", "300", 333), ("2000", "300", 667)])
    func dividingRoundsToTheNearestCent(lhs: String, rhs: String, expected: Int) {
        #expect(calculate(lhs, .divide, rhs).cents == expected)
    }

    @Test func subtractingCanGoBelowZero() {
        let result = calculate("500", .subtract, "1200")

        #expect(result.cents == -700)
        #expect(result.text(locale: usEnglish) == "-7.00")
    }

    @Test func multiplyingAndDividingComeBeforeAddingAndSubtracting() {
        var keys = typing("1000")
        keys.append(.operation(.add))
        keys += typing("200")
        keys.append(.operation(.multiply))
        keys += typing("300")
        keys.append(.equals)

        #expect(entry(keys).cents == 1600)
    }

    @Test func dividingByZeroIsAnErrorWithNoAmount() {
        let result = calculate("1000", .divide, "0")

        #expect(result.cents == nil)
        #expect(result.text(locale: usEnglish) == "Error")
    }

    @Test func aDigitAfterAnErrorStartsOver() {
        var result = calculate("1000", .divide, "0")
        result.press(.digit(5))

        #expect(result.cents == 5)
        #expect(result.text(locale: usEnglish) == "0.05")
    }

    @Test func digitsPastTheLargestAmountAreIgnored() {
        let typed = entry(typing("99999999999") + typing("9"))

        #expect(typed.cents == 99_999_999_999)
        #expect(typed.text(locale: usEnglish) == "999,999,999.99")
    }

    @Test func aResultTooLargeToHoldIsAnError() {
        #expect(calculate("99999999999", .multiply, "99999999999").cents == nil)
    }

    // MARK: Correcting and continuing

    @Test func anOperationWithNothingAfterItIsLeftOutOfTheAmount() {
        let typed = entry(typing("1200") + [.operation(.add)])

        #expect(typed.cents == 1200)
        #expect(typed.text(locale: usEnglish) == "12.00 +")
    }

    @Test func aSecondOperationKeyReplacesTheFirst() {
        var keys = typing("1200")
        keys += [.operation(.add), .operation(.multiply)]
        keys += typing("200")
        keys.append(.equals)

        #expect(entry(keys).cents == 2400)
    }

    @Test func backspaceRemovesTheNumberAfterAnOperationThenTheOperation() {
        var typed = entry(typing("1200") + [.operation(.add)] + typing("5"))

        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "12.00 +")

        typed.press(.backspace)
        #expect(typed.text(locale: usEnglish) == "12.00")
        #expect(typed.cents == 1200)
    }

    @Test func anOperationFirstStartsFromZero() {
        let result = entry([.operation(.subtract)] + typing("500") + [.equals])

        #expect(result.cents == -500)
    }

    @Test func aDigitAfterEqualsStartsANewAmount() {
        var result = calculate("1200", .add, "300")
        result.press(.digit(5))

        #expect(result.cents == 5)
    }

    @Test func anOperationAfterEqualsContinuesFromTheResult() {
        var result = calculate("1200", .add, "300")
        result.press(.operation(.add))
        for key in typing("100") { result.press(key) }
        result.press(.equals)

        #expect(result.cents == 1600)
    }

    @Test func backspaceAfterEqualsTrimsTheResult() {
        var result = calculate("1200", .add, "350")
        result.press(.backspace)

        #expect(result.cents == 155)
    }

    @Test func digitsTypedAfterTrimmingANegativeResultExtendIt() {
        var result = calculate("500", .subtract, "1200")
        result.press(.backspace)
        result.press(.digit(5))

        #expect(result.cents == -705)
    }

    @Test func anEntryCanStartFromAnExistingAmount() {
        let existing = AmountEntry(cents: 1276)

        #expect(existing.cents == 1276)
        #expect(existing.text(locale: usEnglish) == "12.76")
    }

    @Test func typingOverAnExistingAmountReplacesIt() {
        var existing = AmountEntry(cents: 1276)
        existing.press(.digit(5))

        #expect(existing.cents == 5)
    }

    @Test func backspaceTrimsAnExistingAmount() {
        var existing = AmountEntry(cents: 1276)
        existing.press(.backspace)

        #expect(existing.cents == 127)
    }

    // MARK: Typing on a Mac keyboard

    @Test func typingOnAKeyboardIsCentsFirstToo() {
        var typed = AmountEntry()
        for character in "1276" {
            if let key = KeypadKey(typing: character) { typed.press(key) }
        }

        #expect(typed.cents == 1276)
    }

    @Test(arguments: [
        ("+", KeypadKey.operation(.add)), ("-", .operation(.subtract)), ("−", .operation(.subtract)),
        ("*", .operation(.multiply)), ("x", .operation(.multiply)), ("×", .operation(.multiply)),
        ("/", .operation(.divide)), ("÷", .operation(.divide)), ("=", .equals),
        ("\u{7F}", .backspace), ("\u{8}", .backspace), ("c", .allClear), ("C", .allClear),
    ] as [(Character, KeypadKey)])
    func keyboardKeysMatchTheKeypad(character: Character, key: KeypadKey) {
        #expect(KeypadKey(typing: character) == key)
    }

    @Test(arguments: [".", ",", "a", " "] as [Character])
    func otherKeyboardKeysAreIgnored(character: Character) {
        #expect(KeypadKey(typing: character) == nil)
    }
}
