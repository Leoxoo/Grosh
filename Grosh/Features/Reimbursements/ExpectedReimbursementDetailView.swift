import SwiftData
import SwiftUI

/// An Expected reimbursement's detail: who owes, the Expense it is against, the amount (or `?`), what is outstanding,
/// its payments, and Record payment, Close (for an open amount), Forgive and the reminder, or that it was paid back,
/// closed or forgiven, with Reopen or Un-forgive. Use inside a `NavigationStack`.
struct ExpectedReimbursementDetailView: View {
    let expectation: ExpectedReimbursement

    @Environment(\.today) private var today
    @State private var isRecordingPayment = false
    @State private var isForgiving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if expectation.isGone || !expectation.isOfLiveExpense {
                ContentUnavailableView(Strings.OwesMe.expectationDeleted, systemImage: "trash")
            } else {
                details
            }
        }
        .navigationTitle(Strings.OwesMe.owesMe)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isRecordingPayment) {
            ExpectationPaymentEditor(expectation: expectation)
        }
        .sheet(isPresented: $isForgiving) {
            ExpectationForgiveSheet(expectation: expectation)
        }
        .errorAlert(Strings.OwesMe.couldntChange, message: $errorMessage)
    }

    private var details: some View {
        List {
            Section {
                LabeledContent(Strings.Common.from, value: expectation.personName)
                if let expense = expectation.expense {
                    NavigationLink {
                        TransactionDetailView(transaction: expense)
                    } label: {
                        LabeledContent(Strings.Common.expense) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(expectation.expenseTitle)
                                Text(expense.amount.formatted())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                LabeledContent(Strings.OwesMe.expected, value: expectation.expected?.formatted() ?? "?")
                if expectation.hasPayments {
                    LabeledContent(Strings.OwesMe.paidBack, value: expectation.paid.formatted())
                }
                LabeledContent(Strings.DebtsLoans.outstanding) {
                    Text(expectation.outstanding?.formatted() ?? "?")
                        .monospacedDigit()
                        .foregroundStyle(expectation.isOpen ? .primary : .secondary)
                }
                statusRows
            } footer: {
                if expectation.isOpen && expectation.hasOpenAmount {
                    Text(Strings.OwesMe.openAmountFooter)
                } else {
                    Text(Strings.OwesMe.detailFooter)
                }
            }

            if expectation.isOpen {
                Section {
                    Button(Strings.DebtsLoans.recordPayment, systemImage: "plus.circle") { isRecordingPayment = true }
                    if expectation.hasOpenAmount {
                        Button(Strings.Common.close, systemImage: "checkmark.circle") { perform { try expectation.close(on: today) } }
                    }
                    Button(Strings.DebtsLoans.forgive, systemImage: "hand.raised") { isForgiving = true }
                    ReminderField(
                        day: reminderDay, turnsOnAt: ReminderDay.default(after: expectation.expense?.day ?? today)
                    )
                }
            }

            let payments = expectation.payments
            if !payments.isEmpty {
                Section(Strings.OwesMe.payments) {
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
            Label(Strings.Common.settled, systemImage: "checkmark.seal.fill")
                .foregroundStyle(.settled)
        case .closed:
            if let closed = expectation.closedDay {
                LabeledContent(Strings.OwesMe.closed, value: closed.date().formatted(date: .abbreviated, time: .omitted))
            }
            Button(Strings.OwesMe.reopen, systemImage: "arrow.uturn.backward") { perform { try expectation.reopen() } }
        case .forgiven:
            LabeledContent {
                Text(expectation.forgivenDay?.date().formatted(date: .abbreviated, time: .omitted) ?? "")
            } label: {
                Label(Strings.Common.forgiven, systemImage: "hand.raised.fill")
                    .foregroundStyle(.settled)
            }
            if !expectation.forgivenNote.isEmpty {
                LabeledContent(Strings.Common.note, value: expectation.forgivenNote)
            }
            Button(Strings.DebtsLoans.unforgive, systemImage: "arrow.uturn.backward") { perform { try expectation.unforgive() } }
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
        Log.store.perform("Changing Owes me", errorMessage: &errorMessage, change)
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
                    Text(Strings.OwesMe.into(wallet.name))
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
