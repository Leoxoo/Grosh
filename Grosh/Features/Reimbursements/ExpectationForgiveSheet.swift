import SwiftData
import SwiftUI

/// Forgive an Expected reimbursement: the money won't come back. It is marked Forgiven on a day, with an optional note,
/// and counts as settled. No transaction is added and no balance or report changes (ADR-0004, ADR-0010).
struct ExpectationForgiveSheet: View {
    let expectation: ExpectedReimbursement

    @Environment(\.today) private var today
    @Environment(\.dismiss) private var dismiss
    /// The day the user picked, or `nil` while it is still today.
    @State private var pickedDay: CalendarDay?
    @State private var note = ""
    private var saver = SheetSaver(Strings.DebtsLoans.couldntForgive)

    private var day: Binding<CalendarDay> {
        Binding(get: { pickedDay ?? today }, set: { pickedDay = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(Strings.Common.from, value: expectation.personName)
                    LabeledContent(Strings.DebtsLoans.outstanding) {
                        Text(expectation.outstanding.formattedOrUnknown)
                            .monospacedDigit()
                    }
                    DayStepper(title: Strings.Common.date, day: day)
                    TextField(Strings.Common.note, text: $note, axis: .vertical)
                } footer: {
                    Text(Strings.OwesMe.forgiveFooter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Strings.DebtsLoans.forgive)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.DebtsLoans.forgive) {
                        saver.save("Forgiving Owes me") { try expectation.forgive(on: day.wrappedValue, note: note) }
                    }
                }
            }
        }
        .macSheetSize(.shorterForm)
        .failureAlert(saver)
    }
}
