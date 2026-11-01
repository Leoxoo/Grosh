import Foundation

/// A calculator operation on the Keypad. Every number is an amount in cents, and every result is
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

/// A key on the Keypad.
nonisolated enum KeypadKey: Hashable, Sendable {
    case digit(Int)
    /// The region's decimal separator: `.` or `,`.
    case decimalSeparator
    case backspace
    case allClear
    case operation(CalculatorOperation)
    case equals
}

extension KeypadKey {
    /// The Keypad key a character typed on a hardware keyboard stands for. Both `.` and `,` are the decimal separator,
    /// whichever the region uses. `nil` for keys the Keypad doesn't have.
    nonisolated init?(typing character: Character) {
        if character.isASCII, let digit = character.wholeNumberValue {
            self = .digit(digit)
            return
        }
        switch character {
        case ".", ",": self = .decimalSeparator
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

    /// What a key is for, which sets how it looks on the Keypad and how its tick feels: a digit or the separator, C or
    /// delete, or an operator or `=`.
    nonisolated enum Role: Sendable {
        case digit, function, operation
    }

    nonisolated var role: Role {
        switch self {
        case .digit, .decimalSeparator: .digit
        case .backspace, .allClear: .function
        case .operation, .equals: .operation
        }
    }
}

/// An amount being typed on the Keypad, the way it is written: `6`, `6.`, `6.3`. At most two digits go after the
/// decimal separator. The Keypad is also a calculator; every result is rounded to the nearest cent.
nonisolated struct AmountEntry: Hashable, Sendable {
    /// Whether the amount may be typed below zero (ADR-0011).
    enum Kind: Hashable, Sendable {
        /// An amount whose category sets its sign, so it is typed at or above zero: a leading − is refused, and a
        /// calculation coming out below zero is an error.
        case signedByCategory
        /// A balance, which has no category: a leading − makes it negative, and a calculation may come out below
        /// zero.
        case balance
    }

    /// A number followed by the operation typed after it.
    private struct Step: Hashable, Sendable {
        var operand: TypedNumber
        var operation: CalculatorOperation
    }

    let kind: Kind
    /// The numbers and operations typed before the current number.
    private var steps: [Step] = []
    /// The number being typed; `nil` while nothing is, as right after an operation key.
    private var current: TypedNumber?
    /// Set when `current` is a finished amount (a result, or the amount the entry started from): a digit
    /// replaces it instead of being added to it.
    private var isFinished = false
    /// Set when `=` gave no result (dividing by zero); the next key starts over.
    private var isError = false

    /// An empty entry, showing 0.
    init(kind: Kind = .signedByCategory) {
        self.kind = kind
    }

    /// An entry showing `cents` unpadded (12, 12.5), such as a transaction's amount being edited. The first digit
    /// replaces it, backspace trims it, and an operation carries on from it. Zero is an empty entry.
    init(cents: Int, kind: Kind = .signedByCategory) {
        self.kind = kind
        guard cents != 0 else { return }
        current = TypedNumber(cents: cents)
        isFinished = true
    }

    /// Whether nothing has been typed, so a field that may be left open shows its placeholder.
    var isEmpty: Bool { steps.isEmpty && current == nil && !isError }

    /// What the amount comes to now, in cents. An operation with nothing typed after it yet is left out.
    /// `nil` when it can't be worked out, such as when dividing by zero, or when an amount signed by its category
    /// comes out below zero.
    var cents: Int? {
        guard let value else { return nil }
        return kind == .signedByCategory && value < 0 ? nil : value
    }

    /// What the expression comes to, whatever its sign.
    private var value: Int? {
        guard !isError else { return nil }
        var operands = steps.map(\.operand.cents)
        var operations = steps.map(\.operation)
        if let current {
            operands.append(current.cents)
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

    /// Types `key`. Returns `false` when the key is refused, which the Keypad answers with an error tick: a third digit
    /// after the separator, a digit past the largest amount, a leading − on an amount its category signs, or `=` on a
    /// calculation such an amount can't come to.
    @discardableResult
    mutating func press(_ key: KeypadKey) -> Bool {
        if isError {
            self = AmountEntry(kind: kind)
        }
        switch key {
        case .digit(let digit):
            startNumberIfFinished()
            var number = current ?? TypedNumber()
            guard number.append(digit) else { return false }
            current = number
        case .decimalSeparator:
            startNumberIfFinished()
            var number = current ?? TypedNumber()
            number.appendSeparator()
            current = number
        case .backspace:
            backspace()
        case .allClear:
            self = AmountEntry(kind: kind)
            return true
        case .operation(let operation):
            if current == nil, steps.isEmpty, operation == .subtract {
                // A leading minus is the amount's sign, not a subtraction.
                guard kind == .balance else { return false }
                current = TypedNumber(isNegative: true)
            } else if current == nil, !steps.isEmpty {
                steps[steps.count - 1].operation = operation
            } else if let number = current, !number.hasDigits {
                return false
            } else {
                steps.append(Step(operand: current ?? TypedNumber(), operation: operation))
                current = nil
            }
        case .equals:
            return workOut()
        }
        isFinished = false
        return true
    }

    /// Works out a calculation, as `=` does, so the amount is left as one number. Returns `false`, leaving it as it
    /// is, when an amount its category signs would come out below zero.
    @discardableResult
    mutating func workOut() -> Bool {
        guard isCalculation || current != nil else { return true }
        guard let result = value else {
            isError = true
            steps = []
            return true
        }
        guard cents != nil else { return false }
        current = TypedNumber(cents: result)
        isFinished = true
        steps = []
        return true
    }

    private mutating func startNumberIfFinished() {
        if isFinished {
            current = nil
        }
    }

    /// Deletes the last character of the current number. A number deleted to nothing after an operation goes away,
    /// and then the operation itself, so the number before it can be corrected.
    private mutating func backspace() {
        guard var number = current else {
            current = steps.popLast()?.operand
            return
        }
        number.removeLast()
        current = number.isEmpty ? nil : number
    }

    /// What the display shows: the expression, every number as typed (`12 + 3.5`), with the region's grouping.
    func text(locale: Locale = .current) -> String {
        guard !isError else { return String(localized: Strings.Common.error) }
        var parts = steps.flatMap { [$0.operand.text(locale: locale), $0.operation.symbol] }
        if let current {
            parts.append(current.text(locale: locale))
        } else if steps.isEmpty {
            parts.append(TypedNumber().text(locale: locale))
        }
        return parts.joined(separator: " ")
    }

    /// What the amount field shows, as money: the number as typed (`$6.`, `$1,234.5`), or while a calculation is typed,
    /// what it comes to, unpadded. "Error" when it can't be worked out.
    func amountText(currencyCode: String, locale: Locale = .current) -> String {
        let number: TypedNumber
        if isCalculation || isError {
            guard let cents else { return String(localized: Strings.Common.error) }
            number = TypedNumber(cents: cents)
        } else {
            guard cents != nil else { return String(localized: Strings.Common.error) }
            number = current ?? TypedNumber()
        }
        return number.moneyText(currencyCode: currencyCode, locale: locale)
    }
}

/// A number as typed on the Keypad: its sign, the digits before the decimal separator and, once the separator is
/// typed, the up to two digits after it.
private nonisolated struct TypedNumber: Hashable, Sendable {
    /// The largest number of digits before the separator, for amounts up to 999,999,999.99.
    private static let largestWholeDigits = 9

    var isNegative = false
    /// The digits before the separator, with no leading zero but a lone `0`.
    private var whole = ""
    /// The digits after the separator, or `nil` until the separator is typed.
    private var fraction: String?

    init(isNegative: Bool = false) {
        self.isNegative = isNegative
    }

    /// `cents` written without padding: 1250 is `12.5`, 1200 is `12`.
    init(cents: Int) {
        isNegative = cents < 0
        whole = String(cents.magnitude / 100)
        let hundredths = cents.magnitude % 100
        if hundredths != 0 {
            fraction = hundredths.isMultiple(of: 10) ? String(hundredths / 10) : String(format: "%02d", hundredths)
        }
    }

    var cents: Int {
        let fractionCents = Int((fraction ?? "").padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let magnitude = (Int(whole) ?? 0) * 100 + fractionCents
        return isNegative ? -magnitude : magnitude
    }

    var isEmpty: Bool { !isNegative && !hasDigits }

    /// Whether anything but a sign has been typed.
    var hasDigits: Bool { !whole.isEmpty || fraction != nil }

    /// Types a digit, unless it would be a third one after the separator or pass the largest amount.
    mutating func append(_ digit: Int) -> Bool {
        if let fraction {
            guard fraction.count < 2 else { return false }
            self.fraction = fraction + String(digit)
        } else if whole == "0" {
            whole = String(digit)
        } else if whole.isEmpty || whole.count < Self.largestWholeDigits {
            whole += String(digit)
        } else {
            return false
        }
        return true
    }

    /// Types the separator: after `0` when it comes first, and not a second time.
    mutating func appendSeparator() {
        guard fraction == nil else { return }
        if whole.isEmpty {
            whole = "0"
        }
        fraction = ""
    }

    /// Deletes the last character: a digit, the separator, then the sign.
    mutating func removeLast() {
        if let fraction {
            self.fraction = fraction.isEmpty ? nil : String(fraction.dropLast())
        } else if !whole.isEmpty {
            whole.removeLast()
        } else {
            isNegative = false
        }
    }

    /// The number as typed, with the region's grouping and separator: `1,234.5`, `-6.`. Nothing typed is `0`.
    func text(locale: Locale) -> String {
        (isNegative ? "-" : "") + magnitudeText(locale: locale)
    }

    /// The number as typed, as money in the region's way of writing it: `$1,234.5`, `-$6.`, `6,3 €`.
    func moneyText(currencyCode: String, locale: Locale) -> String {
        let pattern = Decimal(isNegative ? -1 : 1)
            .formatted(.currency(code: currencyCode).precision(.fractionLength(0)).locale(locale))
        guard let one = pattern.range(of: "1") else { return text(locale: locale) }
        return pattern.replacingCharacters(in: one, with: magnitudeText(locale: locale))
    }

    private func magnitudeText(locale: Locale) -> String {
        guard hasDigits else { return isNegative ? "" : 0.formatted(.number.locale(locale)) }
        var text = (Int(whole) ?? 0).formatted(.number.grouping(.automatic).locale(locale))
        if let fraction {
            text += (locale.decimalSeparator ?? ".") + fraction
        }
        return text
    }
}
