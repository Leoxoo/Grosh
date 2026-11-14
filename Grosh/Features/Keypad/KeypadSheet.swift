import os
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
///
/// Save makes the change and closes the sheet, the way a ``SheetSaver`` does: a change refused or failed is logged as
/// `saving` and an alert titled `failureTitle` says why.
struct KeypadSheet<Content: View>: View {
    let title: Text
    @Binding var entry: AmountEntry
    /// A second amount the form takes, such as a Purchase's total. Its row types on the same Keypad.
    var secondEntry: Binding<AmountEntry>?
    let canSave: Bool
    /// What Save does, as the log says it.
    let saving: String
    let save: () throws -> AfterSaving
    let size: MacSheetSize
    @ViewBuilder let content: (KeypadSheetFields) -> Content

    @State private var keypad = KeypadTarget()
    @FocusState private var focus: KeypadSheetField?
    private var saver: SheetSaver

    /// A sheet whose Save closes it once `save` has made the change.
    init(
        title: Text, entry: Binding<AmountEntry>, secondEntry: Binding<AmountEntry>? = nil, canSave: Bool,
        size: MacSheetSize = .keypadForm, saving: String, failureTitle: LocalizedStringResource,
        log: Logger = Log.store, save: @escaping () throws -> Void,
        @ViewBuilder content: @escaping (KeypadSheetFields) -> Content
    ) {
        self.init(
            title: title, entry: entry, secondEntry: secondEntry, canSave: canSave, size: size, saving: saving,
            failureTitle: failureTitle, log: log,
            saveThen: {
                try save()
                return .close
            },
            content: content
        )
    }

    /// A sheet whose `saveThen` says whether it closes once Save has run, for one that asks something more first.
    init(
        title: Text, entry: Binding<AmountEntry>, secondEntry: Binding<AmountEntry>? = nil, canSave: Bool,
        size: MacSheetSize = .keypadForm, saving: String, failureTitle: LocalizedStringResource,
        log: Logger = Log.store, saveThen: @escaping () throws -> AfterSaving,
        @ViewBuilder content: @escaping (KeypadSheetFields) -> Content
    ) {
        self.title = title
        _entry = entry
        self.secondEntry = secondEntry
        self.canSave = canSave
        self.size = size
        self.saving = saving
        save = saveThen
        self.content = content
        saver = SheetSaver(failureTitle, log: log)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                content(KeypadSheetFields(entry: $entry, secondEntry: secondEntry, focus: $focus, saver: saver))
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
                    Button(Strings.Common.save) { saver.saveOrStay(saving, save) }
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
        .macSheetSize(size)
        .failureAlert(saver)
    }
}

/// What a ``KeypadSheet``'s form makes its amount rows and text fields with, so they work with the Keypad.
struct KeypadSheetFields {
    @Binding var entry: AmountEntry
    /// The form's second amount, when it takes one.
    let secondEntry: Binding<AmountEntry>?
    /// Which text field has focus, for a form that shows something more while one does.
    let focus: FocusState<KeypadSheetField?>.Binding
    /// Saves as the sheet's Save does, for a form that saves from somewhere else too, such as a question Save asks.
    let saver: SheetSaver

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
