import SwiftUI

/// The fields of a ``KeypadSheet`` that take focus: the amounts, typed on the keypad, and the text fields, which
/// hide it.
enum KeypadSheetField: Hashable {
    case amount, secondAmount, note, withName
}

/// The shell of every sheet that types an amount on ``AmountKeypad``: a grouped form in its own navigation stack,
/// the keypad docked below it, and Cancel and Save. The amount has focus first; tapping its row shows or hides the
/// keypad, and focusing a text field hides it. `content` builds the form's sections, with its amount row and text
/// fields made by the ``KeypadSheetFields`` it is handed.
struct KeypadSheet<Content: View>: View {
    let title: Text
    @Binding var entry: AmountEntry
    /// A second amount the form takes, such as a Purchase's total. Its row types on the same keypad while it has focus.
    var secondEntry: Binding<AmountEntry>? = nil
    let canSave: Bool
    let save: () -> Void
    /// The sheet's smallest and starting height on a Mac.
    var macHeight: (min: CGFloat, ideal: CGFloat) = (560, 640)
    @ViewBuilder let content: (KeypadSheetFields) -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var isKeypadShown = true
    @FocusState private var focus: KeypadSheetField?

    var body: some View {
        NavigationStack {
            Form {
                content(KeypadSheetFields(
                    entry: $entry, secondEntry: secondEntry, focus: $focus, isKeypadShown: $isKeypadShown
                ))
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if isKeypadShown {
                    AmountKeypad(entry: keypadEntry)
                        .background(.bar)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .defaultFocus($focus, .amount)
            .onChange(of: focus) {
                if let focus, focus != .amount, focus != .secondAmount {
                    isKeypadShown = false
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: macHeight.min, idealHeight: macHeight.ideal)
        #endif
    }

    /// The amount the keypad types into: the second one while its row has focus, otherwise the first.
    private var keypadEntry: Binding<AmountEntry> {
        if focus == .secondAmount, let secondEntry {
            return secondEntry
        }
        return $entry
    }
}

/// What a ``KeypadSheet``'s form makes its focusable fields with, so they work with the keypad.
struct KeypadSheetFields {
    @Binding var entry: AmountEntry
    /// The form's second amount, when it takes one.
    let secondEntry: Binding<AmountEntry>?
    /// Which field has focus, for a form that shows something more while one does.
    let focus: FocusState<KeypadSheetField?>.Binding
    @Binding var isKeypadShown: Bool

    /// The row showing the amount typed on the keypad. Tapping it focuses it and shows or hides the keypad.
    func amountRow(_ title: LocalizedStringKey, currencyCode: String, tint: Color = .primary) -> some View {
        AmountRow(title: title, entry: $entry, currencyCode: currencyCode, tint: tint) {
            focus.wrappedValue = .amount
            isKeypadShown.toggle()
        }
        .focused(focus, equals: .amount)
    }

    /// The row showing the form's second amount, such as a Purchase's total, typed on the keypad. Tapping it focuses it
    /// and shows the keypad. Nothing is shown when the form takes no second amount.
    @ViewBuilder
    func secondAmountRow(_ title: LocalizedStringKey, currencyCode: String, tint: Color = .primary) -> some View {
        if let secondEntry {
            AmountRow(title: title, entry: secondEntry, currencyCode: currencyCode, tint: tint) {
                focus.wrappedValue = .secondAmount
                isKeypadShown = true
            }
            .focused(focus, equals: .secondAmount)
        }
    }

    /// The Note field. Focusing it hides the keypad.
    func noteField(_ text: Binding<String>) -> some View {
        TextField("Note", text: text, axis: .vertical)
            .focused(focus, equals: .note)
    }
}
