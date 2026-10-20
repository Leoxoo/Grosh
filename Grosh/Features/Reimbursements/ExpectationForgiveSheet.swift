import SwiftData
import SwiftUI

/// Forgive an Expected reimbursement: the money won't come back. It is marked Forgiven on a day, with an optional note,
/// and counts as settled. No transaction is added and no balance or report changes (ADR-0004, ADR-0010).
struct ExpectationForgiveSheet: View {
    let expectation: ExpectedReimbursement

    @Environment(\.dismiss) private var dismiss
    @State private var day = CalendarDay.today
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("From", value: expectation.personName)
                    LabeledContent("Outstanding") {
                        Text(expectation.outstanding?.formatted() ?? "?")
                            .monospacedDigit()
                    }
                    DayStepper(title: "Date", day: $day)
                    TextField("Note", text: $note, axis: .vertical)
                } footer: {
                    Text("Marks it forgiven without adding any transaction. Nothing in your balances or reports changes, because it never counted in either.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Forgive")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Forgive", action: forgive)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 380)
        #endif
        .errorAlert("Couldn't Forgive", message: $errorMessage)
    }

    private func forgive() {
        do {
            try expectation.forgive(on: day, note: note)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
