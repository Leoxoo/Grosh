import SwiftUI

/// Which amount field a form's Keypad types into, and whether the Keypad is up. A form keeps one in its state and puts
/// its Keypad on with ``SwiftUI/View/keypad(_:)``; each ``AmountRow`` finds it in the environment and sends the Keypad
/// to itself when tapped.
@MainActor @Observable
final class KeypadTarget {
    /// Whether the Keypad is up. On iPhone it turns off when the Keypad is swiped away, like any keyboard.
    var isShown = false
    /// The field the Keypad types into, or `nil` before one is chosen.
    private(set) var field: AnyHashable?
    /// Whether a calculation is typed in that field, so the action key works it out rather than putting the Keypad
    /// away.
    private(set) var isCalculation = false
    /// How many keys the field has refused, so the Keypad gives an error tick for each.
    private(set) var refusals = 0
    /// Where the field keeps its amount. Point it at a field's `@State` (or its parent's), which outlives the field.
    @ObservationIgnored private var entry: Binding<AmountEntry>?

    /// Sends the Keypad to `field`, typing into `entry`, and shows it. An unfinished calculation in the field it typed
    /// into before is worked out first.
    func type(into field: AnyHashable, _ entry: Binding<AmountEntry>) {
        select(field, entry)
        isShown = true
    }

    /// What tapping a field does: puts the Keypad away when it is up and typing there, and otherwise sends it there.
    func tap(_ field: AnyHashable, _ entry: Binding<AmountEntry>) {
        if isShown, field == self.field {
            isShown = false
        } else {
            type(into: field, entry)
        }
    }

    /// Sends the Keypad to `field` without showing it, as typing on a hardware keyboard there does.
    func select(_ field: AnyHashable, _ entry: Binding<AmountEntry>) {
        if field != self.field {
            self.entry?.wrappedValue.workOut()
        }
        self.field = field
        self.entry = entry
        isCalculation = entry.wrappedValue.isCalculation
    }

    /// Whether the Keypad is up and typing into `field`.
    func isTyping(into field: AnyHashable) -> Bool {
        isShown && self.field == field
    }

    /// Types `key` into the field, counting a refusal when it won't take it.
    func press(_ key: KeypadKey) {
        guard let entry else { return }
        var typed = entry.wrappedValue
        if !typed.press(key) {
            refusals += 1
        }
        entry.wrappedValue = typed
        isCalculation = typed.isCalculation
    }

    func hide() {
        isShown = false
    }
}

/// Where a device shows the Keypad.
enum KeypadPlacement {
    /// As the amount fields' keyboard, sliding up and swiping away like one: on iPhone.
    case keyboard
    /// Docked below the form, with a hardware keyboard typing into the field too: on iPad and Mac.
    case docked

    @MainActor static var current: KeypadPlacement {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .keyboard : .docked
        #else
        .docked
        #endif
    }
}

extension View {
    /// Puts `keypad`'s Keypad on this form, typing into the ``AmountRow`` it was last sent to: on iPhone as the amount
    /// fields' keyboard, which swiping the form puts away; on iPad and Mac docked below the form.
    func keypad(_ keypad: KeypadTarget) -> some View {
        modifier(KeypadDock(keypad: keypad))
    }
}

private struct KeypadDock: ViewModifier {
    let keypad: KeypadTarget

    func body(content: Content) -> some View {
        #if os(iOS)
        if KeypadPlacement.current == .keyboard {
            content
                .background {
                    KeypadInput(keypad: keypad, isShown: keypad.isShown)
                        .frame(width: 0, height: 0)
                }
                .scrollDismissesKeyboard(.immediately)
                .environment(keypad)
        } else {
            docked(content)
        }
        #else
        docked(content)
        #endif
    }

    private func docked(_ content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if keypad.isShown {
                    Keypad(target: keypad)
                        .frame(height: Keypad.dockedHeight)
                        .padding(8)
                        .background(.bar)
                }
            }
            .environment(keypad)
    }
}
