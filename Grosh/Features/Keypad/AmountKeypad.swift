import SwiftUI

/// The keypad for typing an amount cents-first: a phone's number pad (1 2 3 at the top, then 00, 0 and delete), with
/// a row above it holding AC on the left and the calculator's operators in green. Pair it with ``AmountRow`` showing the
/// same ``AmountEntry``. Each key ticks the moment a finger lands on it, on a device that gets haptics while the Haptics
/// switch is on.
struct AmountKeypad: View {
    @Binding var entry: AmountEntry
    @AppStorage(SoundsAndHaptics.hapticsKey) private var hapticsOn = SoundsAndHaptics.defaultIsOn

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                key(.allClear, height: 38)
                ForEach([CalculatorOperation.divide, .multiply, .subtract, .add], id: \.self) { operation in
                    key(.operation(operation), height: 38)
                }
                key(.equals, height: 38)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { digits in
                    GridRow {
                        ForEach(digits, id: \.self) { digit in
                            key(.digit(digit))
                        }
                    }
                }
                GridRow {
                    key(.doubleZero)
                    key(.digit(0))
                    key(.backspace)
                }
            }
        }
        .padding(8)
    }

    private func key(_ key: KeypadKey, height: CGFloat = 48) -> some View {
        Button {
            entry.press(key)
        } label: {
            key.label
                .frame(maxWidth: .infinity, minHeight: height)
        }
        .buttonStyle(KeypadButtonStyle(role: key.role, tick: playsTicks ? key.tick.feedback : nil))
        .accessibilityLabel(key.accessibilityLabel)
    }

    private var playsTicks: Bool {
        SoundsAndHaptics.playsHaptics(on: .current, hapticsOn: hapticsOn)
    }
}

private extension KeypadKey {
    @ViewBuilder
    var label: some View {
        switch self {
        case .digit(let digit): Text(verbatim: "\(digit)")
        case .doubleZero: Text(verbatim: "00")
        case .backspace: Image(systemName: "delete.left")
        case .allClear: Text("AC")
        case .operation(let operation): Text(verbatim: operation.symbol)
        case .equals: Text(verbatim: "=")
        }
    }

    var accessibilityLabel: Text {
        switch self {
        case .digit(let digit): Text(verbatim: "\(digit)")
        case .doubleZero: Text("Double zero")
        case .backspace: Text("Delete")
        case .allClear: Text("All clear")
        case .operation(.add): Text("Plus")
        case .operation(.subtract): Text("Minus")
        case .operation(.multiply): Text("Times")
        case .operation(.divide): Text("Divided by")
        case .equals: Text("Equals")
        }
    }
}

private extension KeypadTick {
    /// How the tick feels. Only the system's impact haptics play, so a tick makes no sound and follows the system's
    /// Haptics setting.
    var feedback: SensoryFeedback {
        switch self {
        case .light: .impact(weight: .light)
        case .soft: .impact(flexibility: .soft, intensity: 0.7)
        case .firm: .impact(weight: .medium)
        }
    }
}

/// A rounded calculator key: digits on a light fill, AC and delete on a stronger one, operators in green. It plays
/// `tick` as soon as it is pressed, before it is let go and types.
private struct KeypadButtonStyle: ButtonStyle {
    let role: KeypadKey.Role
    /// `nil` for no tick.
    let tick: SensoryFeedback?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(role == .operation ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(role == .operation ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(background, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect(cornerRadius: 12))
            .sensoryFeedback(trigger: configuration.isPressed) { [tick] _, isPressed in
                isPressed ? tick : nil
            }
    }

    private var background: AnyShapeStyle {
        switch role {
        case .digit: AnyShapeStyle(.fill.tertiary)
        case .function: AnyShapeStyle(.fill.secondary)
        case .operation: AnyShapeStyle(Color.green.gradient)
        }
    }
}

#Preview {
    @Previewable @State var entry = AmountEntry()
    VStack {
        Text(entry.text())
            .font(.largeTitle.monospacedDigit())
        AmountKeypad(entry: $entry)
    }
}
