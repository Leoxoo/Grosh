import SwiftData
import SwiftUI

/// What the Loan or Debt section of the transaction detail opens.
enum LoanOrDebtAction: Hashable, Identifiable {
    case recordPayment, forgive

    var id: Self { self }
}

/// The transaction detail's section for a Loan or Debt: its story (what was lent or borrowed, paid back and
/// forgiven), what is outstanding, Record Payment, Forgive the Rest and the reminder, or that it is settled, or
/// forgiven with Un-forgive. Shows nothing for any other transaction. Use inside a `List`, with
/// ``SwiftUI/View/loanOrDebtSheets(for:action:)`` on the screen to present what `action` opens.
struct LoanOrDebtSection: View {
    let transaction: Transaction
    @Binding var action: LoanOrDebtAction?

    /// Every Loan, Debt and payment, so the section is current as soon as a payment is recorded.
    @Query(DebtsAndLoans.transactions) private var debtLoanTransactions: [Transaction]
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
                LabeledContent("Outstanding") {
                    Text(loanOrDebt.outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(loanOrDebt.isSettled ? .secondary : .primary)
                }
                if let forgiveness = loanOrDebt.forgiveness {
                    ForgivenRows(forgiveness: forgiveness)
                    Button("Un-forgive", systemImage: "arrow.uturn.backward") { unforgive() }
                }
                if !loanOrDebt.isSettled {
                    Button("Record Payment", systemImage: "plus.circle") { action = .recordPayment }
                    Button("Forgive the Rest", systemImage: "hand.raised") { action = .forgive }
                    ReminderField(day: reminderDay)
                } else if loanOrDebt.forgiveness == nil {
                    Label("Settled", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
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
            .errorAlert("Couldn't Change Loan or Debt", message: $errorMessage)
        }
    }

    private func unforgive() {
        do {
            try transaction.unforgive()
        } catch {
            Log.store.failed("Un-forgiving a Loan or Debt", error)
            errorMessage = error.localizedDescription
        }
    }

    /// The Loan's or Debt's reminder day, saved as soon as it changes.
    private var reminderDay: Binding<CalendarDay?> {
        Binding {
            transaction.reminderDay
        } set: { day in
            do {
                try transaction.setReminder(day)
            } catch {
                Log.reminders.failed("Setting a Loan or Debt reminder", error)
                errorMessage = error.localizedDescription
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
            Label("Forgiven", systemImage: "hand.raised.fill")
                .foregroundStyle(.green)
        }
        LabeledContent("Counts As") {
            HStack(spacing: 6) {
                CategoryIcon(category: forgiveness.category, size: 20)
                Text(forgiveness.category?.name ?? String(localized: "Uncategorized"))
            }
        }
        if !forgiveness.note.isEmpty {
            LabeledContent("Note", value: forgiveness.note)
        }
    }
}

extension View {
    /// Presents Record Payment or Forgive the Rest for `transaction` while `action` says which. Attach to the screen,
    /// outside its `List`, so presenting doesn't depend on the list's rows.
    func loanOrDebtSheets(for transaction: Transaction, action: Binding<LoanOrDebtAction?>) -> some View {
        sheet(item: action) { action in
            switch action {
            case .recordPayment: RecordPaymentEditor(original: transaction)
            case .forgive: ForgiveEditor(original: transaction)
            }
        }
    }
}
