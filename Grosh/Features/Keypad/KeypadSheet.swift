import SwiftUI

/// The fields of a ``KeypadSheet`` that take focus: the amount, typed on the keypad, and the text fields, which
/// hide it.
enum KeypadSheetField: Hashable {
    case amount, note, withName
}

/// The shell of every sheet that types an amount on ``AmountKeypad``: a grouped form in its own navigation stack,
/// the keypad docked below it, and Cancel and Save. The amount has focus first; tapping its row shows or hides the
/// keypad, and focusing a text field hides it. `content` builds the form's sections, with its amount row and text
/// fields made by the ``KeypadSheetFields`` it is handed.
struct KeypadSheet<Content: View>: View {
    let title: Text
    @Binding var entry: AmountEntry
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
                content(KeypadSheetFields(entry: $entry, focus: $focus, isKeypadShown: $isKeypadShown))
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if isKeypadShown {
                    AmountKeypad(entry: $entry)
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
                if let focus, focus != .amount {
                    isKeypadShown = false
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: macHeight.min, idealHeight: macHeight.ideal)
        #endif
    }
}

/// What a ``KeypadSheet``'s form makes its focusable fields with, so they work with the keypad.
struct KeypadSheetFields {
    @Binding var entry: AmountEntry
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

    /// The Note field. Focusing it hides the keypad.
    func noteField(_ text: Binding<String>) -> some View {
        TextField("Note", text: text, axis: .vertical)
            .focused(focus, equals: .note)
    }
}
