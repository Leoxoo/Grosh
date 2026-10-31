import SwiftUI

/// The app's own calculator pad for typing an amount, the same on every device (ADR-0011): wide rounded keys of Liquid
/// Glass, the operators tinted green, and the action key in the brand color. It types into whichever field `target`
/// was sent to. Each key ticks the moment a finger lands on it, and a refused key gives an error tick, on a device that
/// gets haptics while the Haptics switch is on. Holding ⌫ repeats.
///
/// ```
/// C   ÷   ×   │ = or hide (tall)
/// 7   8   9   │
/// 4   5   6   │ −
/// 1   2   3   │ +
///  0 (wide)  .│ ⌫
/// ```
struct Keypad: View {
    let target: KeypadTarget

    /// Its height on iPhone, where it is the keyboard: the system keyboard's, above the home indicator.
    static let keyboardHeight: CGFloat = 286
    /// Its height docked below a form on iPad and Mac, padding aside.
    static let dockedHeight: CGFloat = 260

    private static let spacing: CGFloat = 8
    /// The top row is shorter than the digit rows, by this much.
    private static let topRowScale: CGFloat = 0.72

    @AppStorage(SoundsAndHaptics.hapticsKey) private var hapticsOn = SoundsAndHaptics.defaultIsOn

    var body: some View {
        GeometryReader { geometry in
            let spacing = Self.spacing
            // Never below zero, as while the Keypad is first laid out with no room.
            let keyWidth = max(0, (geometry.size.width - 3 * spacing) / 4)
            let rowHeight = max(0, (geometry.size.height - 4 * spacing) / (4 + Self.topRowScale))
            let topHeight = rowHeight * Self.topRowScale
            GlassEffectContainer(spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            key(.allClear)
                            key(.operation(.divide))
                            key(.operation(.multiply))
                        }
                        .frame(height: topHeight)
                        ForEach([[7, 8, 9], [4, 5, 6], [1, 2, 3]], id: \.self) { digits in
                            HStack(spacing: spacing) {
                                ForEach(digits, id: \.self) { key(.digit($0)) }
                            }
                            .frame(height: rowHeight)
                        }
                        HStack(spacing: spacing) {
                            key(.digit(0))
                                .frame(width: 2 * keyWidth + spacing)
                            key(.decimalSeparator)
                        }
                        .frame(height: rowHeight)
                    }
                    VStack(spacing: spacing) {
                        actionKey
                            .frame(height: topHeight + spacing + rowHeight)
                        key(.operation(.subtract))
                            .frame(height: rowHeight)
                        key(.operation(.add))
                            .frame(height: rowHeight)
                        BackspaceKey(target: target, tick: tick(for: .backspace))
                            .frame(height: rowHeight)
                    }
                    .frame(width: keyWidth)
                }
            }
        }
        .sensoryFeedback(trigger: target.refusals) { [playsTicks] _, _ in
            playsTicks ? KeypadTick.error.feedback : nil
        }
    }

    private func key(_ key: KeypadKey) -> some View {
        Button {
            target.press(key)
        } label: {
            key.label
        }
        .buttonStyle(KeypadKeyStyle(look: key.look, tick: tick(for: key)))
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityIdentifier(key.accessibilityIdentifier)
    }

    /// `=` while a calculation is typed; otherwise the key that puts the Keypad away.
    @ViewBuilder
    private var actionKey: some View {
        let style = KeypadKeyStyle(look: .action, tick: tick(for: .equals))
        if target.isCalculation {
            Button {
                target.press(.equals)
            } label: {
                Text(verbatim: "=")
            }
            .buttonStyle(style)
            .accessibilityLabel(Text(Strings.Keypad.equals))
            .accessibilityIdentifier("Keypad.equals")
        } else {
            Button {
                target.hide()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .buttonStyle(style)
            .accessibilityLabel(Text(Strings.Keypad.hideKeyboard))
            .accessibilityIdentifier("Keypad.hide")
        }
    }

    private func tick(for key: KeypadKey) -> SensoryFeedback? {
        playsTicks ? key.tick.feedback : nil
    }

    private var playsTicks: Bool {
        SoundsAndHaptics.playsHaptics(on: .current, hapticsOn: hapticsOn)
    }
}

/// ⌫, which deletes once when tapped, and again and again while held.
private struct BackspaceKey: View {
    let target: KeypadTarget
    let tick: SensoryFeedback?

    /// Set once holding the key has deleted, so letting go doesn't delete once more.
    @State private var hasRepeated = false

    var body: some View {
        Button {
            if hasRepeated {
                hasRepeated = false
            } else {
                target.press(.backspace)
            }
        } label: {
            KeypadKey.backspace.label
        }
        .buttonStyle(KeypadKeyStyle(look: .function, tick: tick) { hold in
            switch hold {
            case .began:
                hasRepeated = false
            case .repeated:
                hasRepeated = true
                target.press(.backspace)
            }
        })
        .accessibilityLabel(KeypadKey.backspace.accessibilityLabel)
        .accessibilityIdentifier(KeypadKey.backspace.accessibilityIdentifier)
    }
}

/// How a key looks: a digit or the separator in clear glass, C and ⌫ the same, an operator in green glass, and the
/// action key in the brand color.
private enum KeypadKeyLook {
    case digit, function, operation, action
}

private extension KeypadKey {
    var look: KeypadKeyLook {
        switch role {
        case .digit: .digit
        case .function: .function
        case .operation: .operation
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .digit(let digit): Text(verbatim: "\(digit)")
        case .decimalSeparator: Text(verbatim: Locale.current.decimalSeparator ?? ".")
        case .backspace: Image(systemName: "delete.left")
        case .allClear: Text(Strings.Keypad.clearKey)
        case .operation(let operation): Text(verbatim: operation.symbol)
        case .equals: Text(verbatim: "=")
        }
    }

    var accessibilityLabel: Text {
        switch self {
        case .digit(let digit): Text(verbatim: "\(digit)")
        case .decimalSeparator: Text(Strings.Keypad.decimalPoint)
        case .backspace: Text(Strings.Common.delete)
        case .allClear: Text(Strings.Keypad.clear)
        case .operation(.add): Text(Strings.Keypad.plus)
        case .operation(.subtract): Text(Strings.Keypad.minus)
        case .operation(.multiply): Text(Strings.Keypad.times)
        case .operation(.divide): Text(Strings.Keypad.dividedBy)
        case .equals: Text(Strings.Keypad.equals)
        }
    }

    /// How UI tests find the key, whatever its label: `Keypad.4`, `Keypad.decimalSeparator`.
    var accessibilityIdentifier: String {
        switch self {
        case .digit(let digit): "Keypad.\(digit)"
        case .decimalSeparator: "Keypad.decimalSeparator"
        case .backspace: "Keypad.backspace"
        case .allClear: "Keypad.clear"
        case .operation(let operation): "Keypad.\(operation)"
        case .equals: "Keypad.equals"
        }
    }
}

private extension KeypadTick {
    /// How the tick feels. Only the system's haptics play, so a tick makes no sound and follows the system's Haptics
    /// setting.
    var feedback: SensoryFeedback {
        switch self {
        case .light: .impact(weight: .light)
        case .soft: .impact(flexibility: .soft, intensity: 0.7)
        case .firm: .impact(weight: .medium)
        case .error: .error
        }
    }
}

/// What holding a key that repeats does.
private enum KeyHold {
    /// The key went down.
    case began
    /// The key has been held a moment, and then again every little while.
    case repeated
}

/// A wide rounded key of Liquid Glass. It plays `tick` as soon as it is pressed, before it is let go and types, and
/// while held, calls `onHold` again and again.
private struct KeypadKeyStyle: ButtonStyle {
    let look: KeypadKeyLook
    /// `nil` for no tick.
    let tick: SensoryFeedback?
    /// `nil` for a key that doesn't repeat.
    var onHold: (@MainActor (KeyHold) -> Void)? = nil

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(look == .digit ? .regular : .semibold))
            .monospacedDigit()
            .foregroundStyle(look == .action ? AnyShapeStyle(.onBrand) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Self.shape)
            .glassEffect(glass, in: Self.shape)
            .sensoryFeedback(trigger: configuration.isPressed) { [tick] _, isPressed in
                isPressed ? tick : nil
            }
            .task(id: configuration.isPressed) { [isPressed = configuration.isPressed, onHold] in
                guard isPressed, let onHold else { return }
                onHold(.began)
                try? await Task.sleep(for: .milliseconds(450))
                while !Task.isCancelled {
                    onHold(.repeated)
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
    }

    private var glass: Glass {
        switch look {
        case .digit, .function: .regular.interactive()
        case .operation: .regular.tint(.keypadOperator).interactive()
        case .action: .regular.tint(.brand).interactive()
        }
    }
}

#Preview {
    @Previewable @State var entry = AmountEntry()
    @Previewable @State var target = KeypadTarget()
    VStack {
        Text(entry.text())
            .font(.largeTitle.monospacedDigit())
        Keypad(target: target)
            .frame(height: Keypad.dockedHeight)
            .padding(8)
    }
    .onAppear { target.type(into: "preview", $entry) }
}
