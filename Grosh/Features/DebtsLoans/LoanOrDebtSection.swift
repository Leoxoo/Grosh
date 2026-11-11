import SwiftData
import SwiftUI

/// What the Loan or Debt section of the transaction detail opens.
enum LoanOrDebtAction: Hashable, Identifiable {
    case recordPayment, forgive

    var id: Self { self }
}

/// The transaction detail's section for a Loan or Debt: its story (what was lent or borrowed, paid back and
/// forgiven), what is outstanding, Record Payment, Forgive the Rest and the reminder, or that it is settled, or
/// forgiven with Un-forgive. Shows nothing for any other transaction. Use inside a `List`, with the screen presenting
/// ``LoanOrDebtAction/sheet(for:)`` for what `action` opens.
struct LoanOrDebtSection: View {
    let transaction: Transaction
    @Binding var action: LoanOrDebtAction?

    /// Every Loan, Debt and payment, so the section is current as soon as a payment is recorded.
    @Query(DebtsAndLoans.records) private var debtLoanTransactions: [Transaction]
    @State private var errorMessage: String?

    var body: some View {
        if let loanOrDebt = LoanOrDebt(transaction, among: debtLoanTransactions) {
            Section {
                if loanOrDebt.forgiveness != nil || !loanOrDebt.payments.isEmpty {
                    Text(loanOrDebt.kind.story(
                        owed: loanOrDebt.owed, paid: loanOrDebt.paid, forgiven: loanOrDebt.forgiveness?.amount
                    ))
                    .monospacedDigit()
                }
                LabeledContent(Strings.DebtsLoans.outstanding) {
                    Text(loanOrDebt.outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(loanOrDebt.isSettled ? .secondary : .primary)
                }
                if let forgiveness = loanOrDebt.forgiveness {
                    ForgivenRows(forgiveness: forgiveness)
                    Button(Strings.DebtsLoans.unforgive, systemImage: "arrow.uturn.backward") { unforgive() }
                }
                if !loanOrDebt.isSettled {
                    Button(Strings.DebtsLoans.recordPayment, systemImage: "plus.circle") { action = .recordPayment }
                    Button(Strings.DebtsLoans.forgiveTheRest, systemImage: "hand.raised") { action = .forgive }
                    ReminderField(day: reminderDay)
                } else if loanOrDebt.forgiveness == nil {
                    Label(Strings.Common.settled, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.settled)
                }
            } header: {
                Text(loanOrDebt.kind.name)
            } footer: {
                if loanOrDebt.forgiveness != nil {
                    Text(loanOrDebt.kind.forgivenFooter)
                } else if !loanOrDebt.isSettled {
                    Text(loanOrDebt.kind.paymentsFooter)
                }
            }
            .errorAlert(Strings.DebtsLoans.couldntChange, message: $errorMessage)
        }
    }

    private func unforgive() {
        Log.store.perform("Un-forgiving a Loan or Debt", errorMessage: &errorMessage) {
            try transaction.unforgive()
        }
    }

    /// The Loan's or Debt's reminder day, saved as soon as it changes.
    private var reminderDay: Binding<CalendarDay?> {
        Binding {
            transaction.reminderDay
        } set: { day in
            Log.reminders.perform("Setting a Loan or Debt reminder", errorMessage: &errorMessage) {
                try transaction.setReminder(day)
            }
        }
    }
}

/// The Forgiven mark: when, under which category the forgiven amount counts in reports, and its note.
private struct ForgivenRows: View {
    let forgiveness: Forgiveness

    var body: some View {
        LabeledContent {
            Text(forgiveness.day.date().formatted(date: .abbreviated, time: .omitted))
        } label: {
            Label(Strings.Common.forgiven, systemImage: "hand.raised.fill")
                .foregroundStyle(.settled)
        }
        LabeledContent(Strings.DebtsLoans.countsAs) {
            HStack(spacing: 6) {
                CategoryIcon(category: forgiveness.category, size: 20)
                Text(forgiveness.category?.name ?? String(localized: Strings.Common.uncategorized))
            }
        }
        if !forgiveness.note.isEmpty {
            LabeledContent(Strings.Common.note, value: forgiveness.note)
        }
    }
}

extension LoanOrDebtAction {
    /// The sheet this opens for `transaction`: Record Payment or Forgive the Rest. Present it from the screen, outside
    /// its `List`, so presenting doesn't depend on the list's rows.
    @ViewBuilder
    func sheet(for transaction: Transaction) -> some View {
        switch self {
        case .recordPayment: RecordPaymentEditor(original: transaction)
        case .forgive: ForgiveEditor(original: transaction)
        }
    }
}
