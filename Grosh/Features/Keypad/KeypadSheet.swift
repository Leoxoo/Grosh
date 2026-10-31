import SwiftUI

/// The fields of a ``KeypadSheet`` that take focus: the amounts, typed on the Keypad, and the text fields, which
/// put it away.
enum KeypadSheetField: Hashable {
    case amount, secondAmount, note, event
}

/// The shell of every sheet that types an amount: a grouped form in its own navigation stack, the ``Keypad``, and
/// Cancel and Save. The Keypad is up typing the amount when the sheet opens; tapping an amount's row sends it there, or
/// puts it away when it is already typing there, and focusing a text field or swiping the form puts it away (see
/// ``SwiftUI/View/keypad(_:)``). `content` builds the form's sections, with its amount rows and text fields made by the
/// ``KeypadSheetFields`` it is handed; any other ``AmountRow`` in the form types on the same Keypad.
struct KeypadSheet<Content: View>: View {
    let title: Text
    @Binding var entry: AmountEntry
    /// A second amount the form takes, such as a Purchase's total. Its row types on the same Keypad.
    var secondEntry: Binding<AmountEntry>? = nil
    let canSave: Bool
    let save: () -> Void
    /// The sheet's smallest and starting height on a Mac.
    var macHeight: (min: CGFloat, ideal: CGFloat) = (560, 640)
    @ViewBuilder let content: (KeypadSheetFields) -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var keypad = KeypadTarget()
    @FocusState private var focus: KeypadSheetField?

    var body: some View {
        NavigationStack {
            Form {
                content(KeypadSheetFields(entry: $entry, secondEntry: secondEntry, focus: $focus))
            }
            .formStyle(.grouped)
            .keypad(keypad)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.save, action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if keypad.field == nil {
                    keypad.type(into: KeypadSheetField.amount, $entry)
                }
            }
            .onChange(of: focus) {
                if focus == .note || focus == .event {
                    keypad.hide()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: macHeight.min, idealHeight: macHeight.ideal)
        #endif
    }
}

/// What a ``KeypadSheet``'s form makes its amount rows and text fields with, so they work with the Keypad.
struct KeypadSheetFields {
    @Binding var entry: AmountEntry
    /// The form's second amount, when it takes one.
    let secondEntry: Binding<AmountEntry>?
    /// Which text field has focus, for a form that shows something more while one does.
    let focus: FocusState<KeypadSheetField?>.Binding

    /// The row showing the amount typed on the Keypad.
    func amountRow(_ title: LocalizedStringResource, currencyCode: String, tint: Color = .primary) -> some View {
        AmountRow(title, field: KeypadSheetField.amount, entry: $entry, currencyCode: currencyCode, tint: tint)
    }

    /// The row showing the form's second amount, such as a Purchase's total, typed on the same Keypad. Nothing is shown
    /// when the form takes no second amount.
    @ViewBuilder
    func secondAmountRow(_ title: LocalizedStringResource, currencyCode: String, tint: Color = .primary) -> some View {
        if let secondEntry {
            AmountRow(
                title, field: KeypadSheetField.secondAmount, entry: secondEntry, currencyCode: currencyCode, tint: tint
            )
        }
    }

    /// The Note field. Focusing it puts the Keypad away.
    func noteField(_ text: Binding<String>) -> some View {
        TextField(Strings.Common.note, text: text, axis: .vertical)
            .focused(focus, equals: .note)
    }
}
