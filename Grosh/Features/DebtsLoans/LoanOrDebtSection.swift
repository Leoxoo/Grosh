import SwiftData
import SwiftUI

/// What the Loan or Debt section of the transaction detail opens.
enum LoanOrDebtAction: Hashable, Identifiable {
    case recordPayment, forgive

    var id: Self { self }
}

/// The transaction detail's section for a Loan or Debt: what is outstanding, Record Payment, Forgive the Rest and the
/// reminder, or that it is settled. Shows nothing for any other transaction. Use inside a `List`, with
/// ``SwiftUI/View/loanOrDebtSheets(for:action:)`` on the screen to present what `action` opens.
struct LoanOrDebtSection: View {
    let transaction: Transaction
    @Binding var action: LoanOrDebtAction?

    /// Every Loan, Debt and payment, so the section is current as soon as a payment is recorded.
    @Query(DebtsAndLoans.transactions) private var debtLoanTransactions: [Transaction]
    @State private var errorMessage: String?

    var body: some View {
        if let item = LoanOrDebt(transaction, among: debtLoanTransactions) {
            Section {
                LabeledContent("Outstanding") {
                    Text(item.outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(item.isSettled ? .secondary : .primary)
                }
                if item.isSettled {
                    Label("Settled", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Record Payment", systemImage: "plus.circle") { action = .recordPayment }
                    Button("Forgive the Rest", systemImage: "hand.raised") { action = .forgive }
                    ReminderField(day: reminderDay)
                }
            } header: {
                Text(item.isLoan ? "Loan" : "Debt")
            } footer: {
                if !item.isSettled {
                    Text(item.isLoan
                        ? "Payments are recorded as Debt Collections. The Loan itself never changes."
                        : "Payments are recorded as Repayments. The Debt itself never changes.")
                }
            }
            .errorAlert("Couldn't Change Reminder", message: $errorMessage)
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
                errorMessage = error.localizedDescription
            }
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
