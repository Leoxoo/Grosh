import SwiftData
import SwiftUI

/// Forgive an Expected reimbursement: the money won't come back. It is marked Forgiven on a day, with an optional note,
/// and counts as settled. No transaction is added and no balance or report changes (ADR-0004, ADR-0010).
struct ExpectationForgiveSheet: View {
    let expectation: ExpectedReimbursement

    @Environment(\.dismiss) private var dismiss
    @State private var day: CalendarDay
    @State private var note = ""
    @State private var errorMessage: String?

    /// `today` is the day it starts on, from the presenting screen's environment.
    init(expectation: ExpectedReimbursement, today: CalendarDay) {
        self.expectation = expectation
        _day = State(initialValue: today)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(Strings.Common.from, value: expectation.personName)
                    LabeledContent(Strings.DebtsLoans.outstanding) {
                        Text(expectation.outstanding?.formatted() ?? "?")
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
                    Button(Strings.DebtsLoans.forgive, action: forgive)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 380)
        #endif
        .errorAlert(Strings.DebtsLoans.couldntForgive, message: $errorMessage)
    }

    private func forgive() {
        let forgiven = Log.store.perform("Forgiving Owes me", errorMessage: &errorMessage) {
            try expectation.forgive(on: day, note: note)
        }
        if forgiven {
            dismiss()
        }
    }
}
