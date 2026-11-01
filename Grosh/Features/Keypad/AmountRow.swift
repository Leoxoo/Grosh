import SwiftUI

/// A form row showing an amount typed on the form's ``Keypad`` (see ``SwiftUI/View/keypad(_:)``): as typed (`$6.`,
/// `$1,234.5`), and while a calculation is typed, the expression above what it comes to. Tapping the row sends the
/// Keypad to it and shows it, or puts it away when it is already typing here. On iPad and Mac, typing on a hardware
/// keyboard goes into the row too.
struct AmountRow<Label: View>: View {
    /// Which field this is on its form, so the Keypad knows where it types.
    let field: AnyHashable
    /// Keep it in `@State` (the row's own or its form's), which the Keypad can type into after the row is gone.
    @Binding var entry: AmountEntry
    var currencyCode = Money.defaultCurrencyCode
    var tint: Color = .primary
    /// Shown, dimmed, while nothing is typed, for an amount that may be left open, such as "Any"; `nil` shows 0.
    var placeholder: LocalizedStringResource?
    var font: Font = .title2.weight(.semibold)
    @ViewBuilder let label: Label

    @Environment(KeypadTarget.self) private var keypad: KeypadTarget?
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                if entry.isCalculation {
                    Text(entry.text())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let placeholder, entry.isEmpty {
                    Text(placeholder)
                        .font(font)
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.amountText(currencyCode: currencyCode))
                        .font(font)
                        .foregroundStyle(entry.cents == nil ? .invalid : tint)
                        .contentTransition(.numericText())
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 6)
            .background(
                isTypingHere ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8)
            )
        } label: {
            label
        }
        .contentShape(.rect)
        .onTapGesture(perform: tap)
        .amountKeyboardInput(typing: press)
        .focused($hasKeyboardFocus)
        .onChange(of: isTypingHere, initial: true) {
            if isTypingHere, KeypadPlacement.current == .docked {
                hasKeyboardFocus = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, tap)
    }

    private var isTypingHere: Bool {
        keypad?.isTyping(into: field) ?? false
    }

    private func tap() {
        keypad?.tap(field, $entry)
        if KeypadPlacement.current == .docked {
            hasKeyboardFocus = true
        }
    }

    /// A key typed on a hardware keyboard while the row has focus.
    private func press(_ key: KeypadKey) {
        if let keypad {
            keypad.select(field, $entry)
            keypad.press(key)
        } else {
            entry.press(key)
        }
    }
}

extension AmountRow where Label == Text {
    init(
        _ title: LocalizedStringResource, field: AnyHashable, entry: Binding<AmountEntry>,
        currencyCode: String = Money.defaultCurrencyCode, tint: Color = .primary,
        placeholder: LocalizedStringResource? = nil, font: Font = .title2.weight(.semibold)
    ) {
        self.init(
            field: field, entry: entry, currencyCode: currencyCode, tint: tint, placeholder: placeholder, font: font
        ) {
            Text(title)
        }
    }
}

private extension View {
    /// Makes the view focusable and hands the keys typed while it has focus to `press`, as the Keypad's: digits and
    /// the separator (`.` or `,`) as written, `+ - * /` calculate, `=` works it out, delete deletes, `c` clears.
    func amountKeyboardInput(typing press: @escaping (KeypadKey) -> Void) -> some View {
        focusable()
            .onKeyPress(phases: [.down, .repeat]) { keyPress in
                // Leave shortcuts such as ⌘C and ⌘N to the menus.
                guard keyPress.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                let key: KeypadKey? = if keyPress.key == .delete || keyPress.key == .deleteForward {
                    .backspace
                } else {
                    keyPress.characters.first.flatMap(KeypadKey.init(typing:))
                }
                guard let key else { return .ignored }
                press(key)
                return .handled
            }
    }
}
