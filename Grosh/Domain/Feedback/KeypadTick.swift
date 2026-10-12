/// The haptic tick a Keypad key gives the moment a finger lands on it, with no sound. How strong it is follows the
/// key's role.
nonisolated enum KeypadTick: Sendable {
    /// For digits and `00`.
    case light
    /// For AC and delete: softer than a digit's.
    case soft
    /// For `+ − × ÷ =`: firmer than a digit's.
    case firm
}

extension KeypadKey {
    /// The tick the key gives on touch-down: light for digits and `00`, softer for AC and delete, firmer for the
    /// operators and `=`.
    nonisolated var tick: KeypadTick {
        switch role {
        case .digit: .light
        case .function: .soft
        case .operation: .firm
        }
    }
}
