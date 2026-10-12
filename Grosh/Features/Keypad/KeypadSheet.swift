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
    /// Which amount the keypad types into. A row's tap sets it, rather than focus, so the keypad reaches a second
    /// amount whether or not focus lands on its row.
    @State private var typingInto: KeypadSheetField = .amount
    @FocusState private var focus: KeypadSheetField?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    content(KeypadSheetFields(
                        entry: $entry, secondEntry: secondEntry, focus: $focus, isKeypadShown: $isKeypadShown,
                        typingInto: $typingInto
                    ))
                }
                .formStyle(.grouped)
                .safeAreaInset(edge: .bottom) {
                    if isKeypadShown {
                        AmountKeypad(entry: keypadEntry)
                            .background(.bar)
                    }
                }
                .onChange(of: typingInto) { _, newValue in
                    // The keypad covers the bottom of the form, so bring the second amount's row above it.
                    if newValue == .secondAmount {
                        withAnimation { proxy.scrollTo(KeypadSheetField.secondAmount, anchor: .center) }
                    }
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

    /// The amount the keypad types into: the second one once its row is tapped, otherwise the first.
    private var keypadEntry: Binding<AmountEntry> {
        if typingInto == .secondAmount, let secondEntry {
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
    /// Which amount the keypad types into, as the row last tapped sets it.
    @Binding var typingInto: KeypadSheetField

    /// The row showing the amount typed on the keypad. Tapping it focuses it, sends the keypad to it, and shows or
    /// hides the keypad. Tapping it while the keypad types into the second amount sends the keypad back here instead.
    func amountRow(_ title: LocalizedStringKey, currencyCode: String, tint: Color = .primary) -> some View {
        AmountRow(title: title, entry: $entry, currencyCode: currencyCode, tint: tint) {
            focus.wrappedValue = .amount
            if isKeypadShown && typingInto == .amount {
                isKeypadShown = false
            } else {
                typingInto = .amount
                isKeypadShown = true
            }
        }
        .focused(focus, equals: .amount)
    }

    /// The row showing the form's second amount, such as a Purchase's total, typed on the keypad. Tapping it focuses
    /// it, sends the keypad to it, and shows the keypad. Nothing is shown when the form takes no second amount.
    @ViewBuilder
    func secondAmountRow(_ title: LocalizedStringKey, currencyCode: String, tint: Color = .primary) -> some View {
        if let secondEntry {
            AmountRow(title: title, entry: secondEntry, currencyCode: currencyCode, tint: tint) {
                focus.wrappedValue = .secondAmount
                typingInto = .secondAmount
                isKeypadShown = true
            }
            .focused(focus, equals: .secondAmount)
            .id(KeypadSheetField.secondAmount)
        }
    }

    /// The Note field. Focusing it hides the keypad.
    func noteField(_ text: Binding<String>) -> some View {
        TextField("Note", text: text, axis: .vertical)
            .focused(focus, equals: .note)
    }
}
