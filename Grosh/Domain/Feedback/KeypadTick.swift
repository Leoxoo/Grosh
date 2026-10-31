/// The haptic tick a Keypad key gives the moment a finger lands on it, with no sound. How strong it is follows the
/// key's role.
nonisolated enum KeypadTick: Sendable {
    /// For digits and the decimal separator.
    case light
    /// For C and delete: softer than a digit's.
    case soft
    /// For `+ − × ÷ =`: firmer than a digit's.
    case firm
    /// For a key the amount refused, such as a third digit after the separator.
    case error
}

extension KeypadKey {
    /// The tick the key gives on touch-down: light for digits and the separator, softer for C and delete, firmer for
    /// the operators and `=`.
    nonisolated var tick: KeypadTick {
        switch role {
        case .digit: .light
        case .function: .soft
        case .operation: .firm
        }
    }
}
