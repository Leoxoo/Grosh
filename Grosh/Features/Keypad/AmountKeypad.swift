import SwiftUI

/// The Apple Calculator–style keypad for typing an amount cents-first, with green operators.
/// Pair it with ``AmountRow`` showing the same ``AmountEntry``. Each key ticks the moment a finger lands on it, on a
/// device that gets haptics while the Haptics switch is on.
struct AmountKeypad: View {
    @Binding var entry: AmountEntry
    @AppStorage(SoundsAndHaptics.hapticsKey) private var hapticsOn = SoundsAndHaptics.defaultIsOn

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                key(.allClear).gridCellColumns(2)
                key(.backspace)
                key(.operation(.divide))
            }
            GridRow {
                key(.digit(7))
                key(.digit(8))
                key(.digit(9))
                key(.operation(.multiply))
            }
            GridRow {
                key(.digit(4))
                key(.digit(5))
                key(.digit(6))
                key(.operation(.subtract))
            }
            GridRow {
                key(.digit(1))
                key(.digit(2))
                key(.digit(3))
                key(.operation(.add))
            }
            GridRow {
                key(.digit(0)).gridCellColumns(2)
                key(.doubleZero)
                key(.equals)
            }
        }
        .padding(8)
    }

    private func key(_ key: KeypadKey) -> some View {
        Button {
            entry.press(key)
        } label: {
            key.label
                .frame(maxWidth: .infinity, minHeight: 44)
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
        case .allClear: Text(Strings.Keypad.allClearKey)
        case .operation(let operation): Text(verbatim: operation.symbol)
        case .equals: Text(verbatim: "=")
        }
    }

    var accessibilityLabel: Text {
        switch self {
        case .digit(let digit): Text(verbatim: "\(digit)")
        case .doubleZero: Text(Strings.Keypad.doubleZero)
        case .backspace: Text(Strings.Common.delete)
        case .allClear: Text(Strings.Keypad.allClear)
        case .operation(.add): Text(Strings.Keypad.plus)
        case .operation(.subtract): Text(Strings.Keypad.minus)
        case .operation(.multiply): Text(Strings.Keypad.times)
        case .operation(.divide): Text(Strings.Keypad.dividedBy)
        case .equals: Text(Strings.Keypad.equals)
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
            .foregroundStyle(role == .operation ? AnyShapeStyle(.onBrand) : AnyShapeStyle(.primary))
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
        case .operation: AnyShapeStyle(Color.brand.gradient)
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
