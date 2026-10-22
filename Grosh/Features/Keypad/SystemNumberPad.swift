#if os(iOS)
import SwiftUI
import UIKit

/// The iPhone's own number pad typing an amount cents-first into `entry`, with a row on top holding AC on the left, the
/// calculator's operators in green, and a button that puts the keyboard away. It is the system keyboard, so it looks,
/// sounds and swipes away like any other; nothing of it is drawn by the app but the row on top. While `isShown`, it is
/// up; when the keyboard goes away by any means (a swipe, another field taking focus, the button), `isShown` turns off.
/// Takes no room of its own: put it in a view's background.
struct SystemNumberPad: UIViewRepresentable {
    @Binding var entry: AmountEntry
    @Binding var isShown: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> NumberPadInput {
        let input = NumberPadInput()
        input.coordinator = context.coordinator
        return input
    }

    func updateUIView(_ input: NumberPadInput, context: Context) {
        context.coordinator.parent = self
        if isShown, !input.isFirstResponder {
            // Not while SwiftUI is still updating the screen that holds it.
            DispatchQueue.main.async { input.becomeFirstResponder() }
        } else if !isShown, input.isFirstResponder {
            input.resignFirstResponder()
        }
    }

    final class Coordinator {
        var parent: SystemNumberPad

        init(parent: SystemNumberPad) {
            self.parent = parent
        }

        func press(_ key: KeypadKey) {
            parent.entry.press(key)
        }

        func hide() {
            parent.isShown = false
        }

        func didHide() {
            guard parent.isShown else { return }
            DispatchQueue.main.async { self.parent.isShown = false }
        }
    }
}

/// What the number pad types into: an invisible view that takes the keyboard's keys and hands them to the entry.
final class NumberPadInput: UIView, UIKeyInput {
    var coordinator: SystemNumberPad.Coordinator?
    var keyboardType: UIKeyboardType = .numberPad

    private lazy var accessory: UIView = {
        let host = UIHostingController(rootView: OperationsRow { [weak self] action in
            switch action {
            case .press(let key): self?.coordinator?.press(key)
            case .hide: self?.coordinator?.hide()
            }
        })
        host.view.frame = CGRect(x: 0, y: 0, width: 0, height: 52)
        host.view.autoresizingMask = .flexibleWidth
        host.view.backgroundColor = .clear
        return host.view
    }()

    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { accessory }

    var hasText: Bool { true }

    func insertText(_ text: String) {
        for digit in text.compactMap(\.wholeNumberValue) {
            coordinator?.press(.digit(digit))
        }
    }

    func deleteBackward() {
        coordinator?.press(.backspace)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            coordinator?.didHide()
        }
        return didResign
    }
}

/// The row on top of the number pad: AC, ÷ × − + =, and the button that puts the keyboard away.
private struct OperationsRow: View {
    enum Action {
        case press(KeypadKey)
        case hide
    }

    let perform: (Action) -> Void

    var body: some View {
        HStack(spacing: 6) {
            key(Text("AC"), isOperator: false) { perform(.press(.allClear)) }
                .accessibilityLabel("All clear")
            ForEach([CalculatorOperation.divide, .multiply, .subtract, .add], id: \.self) { operation in
                key(Text(verbatim: operation.symbol), isOperator: true) { perform(.press(.operation(operation))) }
            }
            key(Text(verbatim: "="), isOperator: true) { perform(.press(.equals)) }
                .accessibilityLabel("Equals")
            key(Image(systemName: "keyboard.chevron.compact.down"), isOperator: false) { perform(.hide) }
                .accessibilityLabel("Hide Keyboard")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// One key of the row, as wide as the others: an operator on green, AC and Hide on the keyboard's own key gray.
    private func key(_ label: some View, isOperator: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isOperator ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(
                    isOperator ? AnyShapeStyle(Color.green) : AnyShapeStyle(.fill.secondary),
                    in: .rect(cornerRadius: 8)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
#endif
