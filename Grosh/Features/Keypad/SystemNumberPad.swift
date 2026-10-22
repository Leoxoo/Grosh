#if os(iOS)
import SwiftUI
import UIKit

/// The iPhone's own number pad typing an amount cents-first into `entry`, with a row of keys floating on top of it: AC
/// on the left, the calculator's operators in green, and on the right `=` while there is a calculation to work out, or
/// otherwise a key that puts the keyboard away. It is the system keyboard, so it looks, sounds and swipes away like any
/// other; nothing of it is drawn by the app but the row on top. While `isShown`, it is up; when the keyboard goes away
/// by any means (a swipe, another field taking focus, the key), `isShown` turns off. Takes no room of its own: put it in
/// a view's background.
struct SystemNumberPad: UIViewRepresentable {
    @Binding var entry: AmountEntry
    @Binding var isShown: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> NumberPadInput {
        NumberPadInput(coordinator: context.coordinator)
    }

    func updateUIView(_ input: NumberPadInput, context: Context) {
        context.coordinator.parent = self
        input.showCalculation(entry.isCalculation)
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

        func perform(_ action: OperationsRow.Action) {
            switch action {
            case .press(let key): parent.entry.press(key)
            case .hide: parent.isShown = false
            }
        }

        func didHide() {
            guard parent.isShown else { return }
            DispatchQueue.main.async { self.parent.isShown = false }
        }
    }
}

/// What the number pad types into: an invisible view that takes the keyboard's keys and hands them to the entry.
final class NumberPadInput: UIView, UIKeyInput {
    private let coordinator: SystemNumberPad.Coordinator
    private let row: UIHostingController<OperationsRow>
    var keyboardType: UIKeyboardType = .numberPad

    init(coordinator: SystemNumberPad.Coordinator) {
        self.coordinator = coordinator
        row = UIHostingController(rootView: OperationsRow(isCalculation: false, perform: coordinator.perform))
        row.view.frame = CGRect(x: 0, y: 0, width: 0, height: 52)
        row.view.autoresizingMask = .flexibleWidth
        row.view.backgroundColor = .clear
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Shows `=` on the last key while a calculation is typed, and the key that hides the keyboard otherwise.
    func showCalculation(_ isCalculation: Bool) {
        guard row.rootView.isCalculation != isCalculation else { return }
        row.rootView = OperationsRow(isCalculation: isCalculation, perform: coordinator.perform)
    }

    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { row.view }

    var hasText: Bool { true }

    func insertText(_ text: String) {
        for digit in text.compactMap(\.wholeNumberValue) {
            coordinator.perform(.press(.digit(digit)))
        }
    }

    func deleteBackward() {
        coordinator.perform(.press(.backspace))
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            coordinator.didHide()
        }
        return didResign
    }
}

/// The keys floating on top of the number pad, in glass like the system's own controls: AC, ÷ × − +, and `=` or the
/// key that hides the keyboard.
struct OperationsRow: View {
    enum Action {
        case press(KeypadKey)
        case hide
    }

    /// Whether a calculation is typed, so the last key works it out rather than hiding the keyboard.
    let isCalculation: Bool
    let perform: (Action) -> Void

    var body: some View {
        HStack(spacing: 8) {
            key(isOperator: false) { perform(.press(.allClear)) } label: { Text("AC") }
                .accessibilityLabel("All clear")
            ForEach([CalculatorOperation.divide, .multiply, .subtract, .add], id: \.self) { operation in
                key(isOperator: true) { perform(.press(.operation(operation))) } label: {
                    Text(verbatim: operation.symbol)
                }
            }
            if isCalculation {
                key(isOperator: true) { perform(.press(.equals)) } label: { Text(verbatim: "=") }
                    .accessibilityLabel("Equals")
            } else {
                key(isOperator: false) { perform(.hide) } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide Keyboard")
            }
        }
        .font(.body.weight(.semibold))
        .tint(.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .animation(.snappy, value: isCalculation)
    }

    /// One capsule key, as wide as the others: an operator in green glass, AC and Hide in clear glass.
    @ViewBuilder
    private func key(
        isOperator: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> some View
    ) -> some View {
        let button = Button(action: action) {
            label().frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonBorderShape(.capsule)
        if isOperator {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(.primary)
        }
    }
}
#endif
