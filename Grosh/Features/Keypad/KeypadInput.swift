#if os(iOS)
import SwiftUI
import UIKit

/// The iPhone's Keypad as the amount fields' keyboard: an invisible text field whose keyboard is the app's own
/// ``Keypad``, so it slides up, sits at the keyboard's height and swipes away like any keyboard. While `isShown`, it is
/// up; when it goes away by any means (a swipe, a text field taking the keyboard, the hide key), the keypad's `isShown`
/// turns off. Takes no room of its own: put it in a view's background.
struct KeypadInput: UIViewRepresentable {
    let keypad: KeypadTarget
    let isShown: Bool

    func makeUIView(context: Context) -> KeypadInputField {
        KeypadInputField(keypad: keypad)
    }

    func updateUIView(_ input: KeypadInputField, context: Context) {
        if isShown, !input.isFirstResponder {
            // Not while SwiftUI is still updating the screen that holds it.
            DispatchQueue.main.async { input.becomeFirstResponder() }
        } else if !isShown, input.isFirstResponder {
            input.resignFirstResponder()
        }
    }
}

/// What the Keypad types through on iPhone: an empty text field that never holds text of its own, with the Keypad as
/// its input view. A text field rather than a plain view taking keys, so a hardware keyboard types into it too, and the
/// system describes it as one thing to VoiceOver and to UI tests.
final class KeypadInputField: UITextField, UITextFieldDelegate {
    private let keypad: KeypadTarget
    private let pad: UIHostingController<Keypad>

    init(keypad: KeypadTarget) {
        self.keypad = keypad
        pad = UIHostingController(rootView: Keypad(target: keypad))
        super.init(frame: .zero)
        pad.view.backgroundColor = .clear
        pad.view.translatesAutoresizingMaskIntoConstraints = false
        let container = UIInputView(
            frame: CGRect(x: 0, y: 0, width: 0, height: Keypad.keyboardHeight), inputViewStyle: .keyboard
        )
        container.allowsSelfSizing = true
        container.addSubview(pad.view)
        let margin: CGFloat = 8
        let safeArea = container.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            pad.view.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: margin),
            pad.view.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -margin),
            pad.view.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            pad.view.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -margin),
            pad.view.heightAnchor.constraint(equalToConstant: Keypad.keyboardHeight - 2 * margin),
        ])
        inputView = container
        // A number pad, as far as the text system knows, so it asks for no predictions: with the Keypad in the
        // keyboard's place there is no bar to show them in, and the keyboard logs an error for each one.
        keyboardType = .numberPad
        autocorrectionType = .no
        spellCheckingType = .no
        inlinePredictionType = .no
        tintColor = .clear
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Always, so a hardware keyboard's delete key still reaches the field while it is empty.
    override var hasText: Bool { true }

    /// What a hardware keyboard types goes to the Keypad, and the field stays empty.
    func textField(
        _ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String
    ) -> Bool {
        for key in string.compactMap(KeypadKey.init(typing:)) {
            keypad.press(key)
        }
        return false
    }

    /// A hardware keyboard's delete key, which an empty field still hears.
    override func deleteBackward() {
        keypad.press(.backspace)
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, keypad.isShown {
            DispatchQueue.main.async { self.keypad.hide() }
        }
        return didResign
    }
}
#endif
