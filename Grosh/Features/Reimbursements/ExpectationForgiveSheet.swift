import SwiftData
import SwiftUI

/// Forgive an Expected reimbursement: the money won't come back. It is marked Forgiven on a day, with an optional note,
/// and counts as settled. No transaction is added and no balance or report changes (ADR-0004, ADR-0010).
struct ExpectationForgiveSheet: View {
    let expectation: ExpectedReimbursement

    @Environment(\.today) private var today

    var body: some View {
        MadeOnce {
            today
        } content: { day in
            ExpectationForgiveForm(expectation: expectation, startingDay: day)
        }
    }
}

/// The form behind ``ExpectationForgiveSheet``, holding the day from the moment the sheet opens.
private struct ExpectationForgiveForm: View {
    let expectation: ExpectedReimbursement

    @Environment(\.dismiss) private var dismiss
    @State private var day: CalendarDay
    @State private var note = ""
    private var saver = SheetSaver(Strings.DebtsLoans.couldntForgive)

    init(expectation: ExpectedReimbursement, startingDay: CalendarDay) {
        self.expectation = expectation
        _day = State(initialValue: startingDay)
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
                    DayStepper(title: Strings.Common.date, day: $day)
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
                        saver.save("Forgiving Owes me") { try expectation.forgive(on: day, note: note) }
                    }
                }
            }
        }
        .macSheetSize(.shorterForm)
        .failureAlert(saver)
    }
}
