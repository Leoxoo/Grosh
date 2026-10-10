import Foundation

/// A calculator operation on the amount keypad. Every number is an amount in cents, and every result is
/// rounded to the nearest cent, half away from zero.
nonisolated enum CalculatorOperation: Hashable, Sendable, CaseIterable {
    case add, subtract, multiply, divide

    var symbol: String {
        switch self {
        case .add: "+"
        case .subtract: "−"
        case .multiply: "×"
        case .divide: "÷"
        }
    }

    /// Multiplying and dividing come before adding and subtracting.
    fileprivate var isMultiplicative: Bool { self == .multiply || self == .divide }

    /// Applies the operation to two amounts in cents: 12.00 × 3.00 is 36.00, and 10.00 ÷ 3.00 is 3.33.
    /// `nil` when the result can't be worked out: dividing by zero, or a result too large to hold.
    fileprivate func apply(_ lhs: Int, _ rhs: Int) -> Int? {
        switch self {
        case .add:
            Self.checked(lhs.addingReportingOverflow(rhs))
        case .subtract:
            Self.checked(lhs.subtractingReportingOverflow(rhs))
        case .multiply:
            Self.checked(lhs.multipliedReportingOverflow(by: rhs)).map { Self.roundedQuotient($0, 100) }
        case .divide:
            rhs == 0 ? nil : Self.checked(lhs.multipliedReportingOverflow(by: 100)).map { Self.roundedQuotient($0, rhs) }
        }
    }

    private static func checked(_ result: (partialValue: Int, overflow: Bool)) -> Int? {
        result.overflow ? nil : result.partialValue
    }

    /// `dividend / divisor` rounded half away from zero.
    private static func roundedQuotient(_ dividend: Int, _ divisor: Int) -> Int {
        let quotient = dividend / divisor
        let remainder = dividend % divisor
        guard 2 * remainder.magnitude >= divisor.magnitude else { return quotient }
        return quotient + ((dividend < 0) == (divisor < 0) ? 1 : -1)
    }
}

/// A key on the amount keypad.
nonisolated enum KeypadKey: Hashable, Sendable {
    case digit(Int)
    case doubleZero
    case backspace
    case allClear
    case operation(CalculatorOperation)
    case equals
}

extension KeypadKey {
    /// The keypad key a character typed on a hardware keyboard stands for, so typing on a Mac is cents-first too.
    /// `nil` for keys the keypad doesn't have, such as the decimal point.
    nonisolated init?(typing character: Character) {
        if character.isASCII, let digit = character.wholeNumberValue {
            self = .digit(digit)
            return
        }
        switch character {
        case "+": self = .operation(.add)
        case "-", "−": self = .operation(.subtract)
        case "*", "x", "X", "×": self = .operation(.multiply)
        case "/", "÷": self = .operation(.divide)
        case "=": self = .equals
        case "\u{7F}", "\u{8}": self = .backspace
        case "c", "C": self = .allClear
        default: return nil
        }
    }
}

/// An amount being typed on the cents-first keypad: each digit is a cent, so `1276` is 12.76.
/// The keypad is also a calculator; every number in an expression is an amount in cents.
nonisolated struct AmountEntry: Hashable, Sendable {
    /// A number followed by the operation typed after it.
    private struct Step: Hashable, Sendable {
        var operand: Int
        var operation: CalculatorOperation
    }

    /// The largest number that can be typed: 999,999,999.99.
    private static let largestTypedCents = 99_999_999_999

    /// The numbers and operations typed before the current number.
    private var steps: [Step] = []
    /// The number being typed, in cents; `nil` right after an operation key.
    private var current: Int?
    /// Set when `current` is a finished amount (a result, or the amount the entry started from): a digit
    /// replaces it instead of being added to it.
    private var isFinished = false
    /// Set when `=` gave no result (dividing by zero); the next key starts over.
    private var isError = false

    /// An empty entry, showing 0.00.
    init() {}

    /// An entry showing `cents`, such as a transaction's amount being edited. Typing a digit replaces it;
    /// backspace trims it.
    init(cents: Int) {
        current = cents
        isFinished = true
    }

    /// What the amount comes to now, in cents. An operation with nothing typed after it yet is left out.
    /// `nil` when it can't be worked out, such as when dividing by zero.
    var cents: Int? {
        guard !isError else { return nil }
        var operands = steps.map(\.operand)
        var operations = steps.map(\.operation)
        if let current {
            operands.append(current)
        } else if !operations.isEmpty {
            operations.removeLast()
        }
        guard !operands.isEmpty else { return 0 }
        // × and ÷ first, left to right, folding each into the term before it.
        var terms = [operands[0]]
        var termOperations: [CalculatorOperation] = []
        for (operation, operand) in zip(operations, operands.dropFirst()) {
            if operation.isMultiplicative {
                guard let product = operation.apply(terms[terms.count - 1], operand) else { return nil }
                terms[terms.count - 1] = product
            } else {
                terms.append(operand)
                termOperations.append(operation)
            }
        }
        // Then + and −, left to right.
        var total = terms[0]
        for (operation, term) in zip(termOperations, terms.dropFirst()) {
            guard let sum = operation.apply(total, term) else { return nil }
            total = sum
        }
        return total
    }

    /// Whether an operation has been typed and `=` not yet pressed, so the display shows an expression
    /// rather than a single amount.
    var isCalculation: Bool { !steps.isEmpty }

    mutating func press(_ key: KeypadKey) {
        if isError {
            self = AmountEntry()
        }
        switch key {
        case .digit(let digit):
            startNumberIfFinished()
            append(digit)
        case .doubleZero:
            startNumberIfFinished()
            append(0)
            append(0)
        case .backspace:
            backspace()
        case .allClear:
            self = AmountEntry()
        case .operation(let operation):
            if current == nil, !steps.isEmpty {
                steps[steps.count - 1].operation = operation
            } else {
                steps.append(Step(operand: current ?? 0, operation: operation))
                current = nil
            }
        case .equals:
            if let result = cents {
                current = result
                isFinished = true
            } else {
                isError = true
            }
            steps = []
            return
        }
        isFinished = false
    }

    /// Turns what the amount comes to into its negative, and back: a balance above zero becomes a debt of the same
    /// size. A calculation is worked out first, and the next digit starts a new amount. An error stays an error.
    mutating func changeSign() {
        guard let cents else { return }
        self = AmountEntry(cents: -cents)
    }

    private mutating func startNumberIfFinished() {
        if isFinished {
            current = nil
        }
    }

    /// Trims the last digit of the current number. A number trimmed to nothing after an operation goes away,
    /// and then the operation itself, so the number before it can be corrected.
    private mutating func backspace() {
        guard let number = current else {
            current = steps.popLast()?.operand
            return
        }
        let trimmed = number / 10
        current = trimmed == 0 && !steps.isEmpty ? nil : trimmed
    }

    /// Types one more digit onto the current number (a trimmed negative result stays negative), unless it would
    /// pass the largest amount.
    private mutating func append(_ digit: Int) {
        let number = current ?? 0
        guard number.magnitude <= Self.largestTypedCents / 10 else { return }
        current = number * 10 + (number < 0 ? -digit : digit)
    }

    /// What the display shows: the expression, every amount with exactly two decimals (`12.00 + 3.50`).
    func text(locale: Locale = .current) -> String {
        guard !isError else { return String(localized: "Error") }
        var parts = steps.flatMap { [Self.format($0.operand, locale), $0.operation.symbol] }
        if current != nil || steps.isEmpty {
            parts.append(Self.format(current ?? 0, locale))
        }
        return parts.joined(separator: " ")
    }

    private static func format(_ cents: Int, _ locale: Locale) -> String {
        (Decimal(cents) / 100).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
}
