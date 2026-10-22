import SwiftData
import SwiftUI

/// An Expected reimbursement's detail: who owes, the Expense it is against, the amount (or `?`), what is outstanding,
/// its payments, and Record payment, Close (for an open amount), Forgive and the reminder, or that it was paid back,
/// closed or forgiven, with Reopen or Un-forgive. Use inside a `NavigationStack`.
struct ExpectedReimbursementDetailView: View {
    let expectation: ExpectedReimbursement

    @State private var isRecordingPayment = false
    @State private var isForgiving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if expectation.isDeleted || expectation.modelContext == nil || !expectation.isOfLiveExpense {
                ContentUnavailableView("Expectation Deleted", systemImage: "trash")
            } else {
                details
            }
        }
        .navigationTitle("Owes Me")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isRecordingPayment) {
            ExpectationPaymentEditor(expectation: expectation)
        }
        .sheet(isPresented: $isForgiving) {
            ExpectationForgiveSheet(expectation: expectation)
        }
        .errorAlert("Couldn't Change Owes Me", message: $errorMessage)
    }

    private var details: some View {
        List {
            Section {
                LabeledContent("From", value: expectation.personName)
                if let expense = expectation.expense {
                    NavigationLink {
                        TransactionDetailView(transaction: expense)
                    } label: {
                        LabeledContent("Expense") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(expectation.expenseTitle)
                                Text(expense.amount.formatted())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                LabeledContent("Expected", value: expectation.expected?.formatted() ?? "?")
                if expectation.hasPayments {
                    LabeledContent("Paid Back", value: expectation.paid.formatted())
                }
                LabeledContent("Outstanding") {
                    Text(expectation.outstanding?.formatted() ?? "?")
                        .monospacedDigit()
                        .foregroundStyle(expectation.isOpen ? .primary : .secondary)
                }
                statusRows
            } footer: {
                if expectation.isOpen && expectation.hasOpenAmount {
                    Text("It has no amount yet, so it is left out of totals. Close it by hand once it is settled.")
                } else {
                    Text("Owes me never changes a balance or a report. Money that comes back is a reimbursement of the expense.")
                }
            }

            if expectation.isOpen {
                Section {
                    Button("Record Payment", systemImage: "plus.circle") { isRecordingPayment = true }
                    if expectation.hasOpenAmount {
                        Button("Close", systemImage: "checkmark.circle") { perform { try expectation.close() } }
                    }
                    Button("Forgive", systemImage: "hand.raised") { isForgiving = true }
                    ReminderField(day: reminderDay, turnsOnAt: ExpectedReimbursement.defaultReminderDay(
                        expenseOn: expectation.expense?.day ?? .today
                    ))
                }
            }

            let payments = expectation.payments
            if !payments.isEmpty {
                Section("Payments") {
                    ForEach(payments) { payment in
                        PaymentRow(payment: payment)
                    }
                }
            }
        }
    }

    /// Where it stands, once it isn't open.
    @ViewBuilder
    private var statusRows: some View {
        switch expectation.status {
        case .open:
            EmptyView()
        case .paidBack:
            Label("Settled", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .closed:
            if let closed = expectation.closedDay {
                LabeledContent("Closed", value: closed.date().formatted(date: .abbreviated, time: .omitted))
            }
            Button("Reopen", systemImage: "arrow.uturn.backward") { perform { try expectation.reopen() } }
        case .forgiven:
            LabeledContent {
                Text(expectation.forgivenDay?.date().formatted(date: .abbreviated, time: .omitted) ?? "")
            } label: {
                Label("Forgiven", systemImage: "hand.raised.fill")
                    .foregroundStyle(.green)
            }
            if !expectation.forgivenNote.isEmpty {
                LabeledContent("Note", value: expectation.forgivenNote)
            }
            Button("Un-forgive", systemImage: "arrow.uturn.backward") { perform { try expectation.unforgive() } }
        }
    }

    /// The reminder day, saved as soon as it changes.
    private var reminderDay: Binding<CalendarDay?> {
        Binding {
            expectation.reminderDay
        } set: { day in
            perform { try expectation.setReminder(day) }
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One payment: its day and note on the left, the amount on the right, and for money that came into another wallet the
/// wallet's name.
private struct PaymentRow: View {
    let payment: ExpectationPayment

    var body: some View {
        LabeledContent {
            AmountText(amount: payment.amount, showsPlusSign: true)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.day.date().formatted(date: .abbreviated, time: .omitted))
                if payment.isElsewhere, let wallet = payment.wallet {
                    Text("Into \(wallet.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !payment.note.isEmpty {
                    Text(payment.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
