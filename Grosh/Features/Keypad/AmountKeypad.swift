import SwiftUI

/// The Apple Calculator–style keypad for typing an amount cents-first, with green operators.
/// Pair it with ``AmountRow`` showing the same ``AmountEntry``.
struct AmountKeypad: View {
    @Binding var entry: AmountEntry

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
        .buttonStyle(KeypadButtonStyle(role: key.role))
        .accessibilityLabel(key.accessibilityLabel)
    }
}

private extension KeypadKey {
    enum Role {
        case digit, function, operation
    }

    var role: Role {
        switch self {
        case .digit, .doubleZero: .digit
        case .backspace, .allClear: .function
        case .operation, .equals: .operation
        }
    }

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

/// A rounded calculator key: digits on a light fill, AC and delete on a stronger one, operators in green.
private struct KeypadButtonStyle: ButtonStyle {
    let role: KeypadKey.Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(role == .operation ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(role == .operation ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(background, in: .rect(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.rect(cornerRadius: 12))
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
