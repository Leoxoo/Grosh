import SwiftUI

/// A form row showing an amount typed on ``AmountKeypad``: always with two decimals, and while a calculation is
/// typed, the expression above what it comes to. Tapping the row calls `onTap` (show the keypad there). When the
/// row has keyboard focus, typing on a Mac or hardware keyboard goes straight into it, cents-first.
struct AmountRow: View {
    let title: LocalizedStringKey
    @Binding var entry: AmountEntry
    var currencyCode = Money.defaultCurrencyCode
    var tint: Color = .primary
    var onTap: () -> Void = {}

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                if entry.isCalculation {
                    Text(entry.text())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(result)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(entry.cents == nil ? .red : tint)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        .amountKeyboardInput($entry)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onTap)
    }

    /// What the amount comes to, as money.
    private var result: String {
        guard let cents = entry.cents else { return String(localized: "Error") }
        return Money(cents: cents, currencyCode: currencyCode).formatted()
    }
}

extension View {
    /// Makes the view focusable and sends keys typed while it has focus to `entry`, as the keypad would:
    /// digits are cents-first, `+ - * /` calculate, `=` works it out, delete trims, `c` clears.
    func amountKeyboardInput(_ entry: Binding<AmountEntry>) -> some View {
        focusable()
            .onKeyPress(phases: [.down, .repeat]) { press in
                // Leave shortcuts such as ⌘C and ⌘N to the menus.
                guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                let key: KeypadKey? = if press.key == .delete || press.key == .deleteForward {
                    .backspace
                } else {
                    press.characters.first.flatMap(KeypadKey.init(typing:))
                }
                guard let key else { return .ignored }
                entry.wrappedValue.press(key)
                return .handled
            }
    }
}
