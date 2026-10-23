import SwiftData
import SwiftUI

extension View {
    /// Adds the Home bell to the toolbar: it shows whether any Loan, Debt or estimated amount is due, and opens the
    /// list of due ones. Use inside the tab's `NavigationStack`.
    func dueRemindersBell() -> some View {
        modifier(DueRemindersBell())
    }
}

/// The bell and the sheet it opens. The sheet hangs off the screen rather than the toolbar button, so rebuilding the
/// toolbar never closes it.
private struct DueRemindersBell: ViewModifier {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @Query(EstimatedAmounts.transactions) private var estimates: [Transaction]
    @Environment(\.today) private var today
    @State private var isShowingList = false

    func body(content: Content) -> some View {
        let dueCount = DebtsAndLoans(transactions).due(on: today).count
            + EstimatedAmounts(estimates).due(on: today).count
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DueRemindersButton(dueCount: dueCount) { isShowingList = true }
                }
            }
            .sheet(isPresented: $isShowingList) {
                DueRemindersList()
            }
    }
}

/// The open Loans and Debts whose reminder day has come, the earliest first, then the estimated amounts waiting for
/// their real figures. A Loan or Debt opens its transaction detail; an estimate opens its amount editor.
private struct DueRemindersList: View {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @Query(EstimatedAmounts.transactions) private var estimates: [Transaction]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.today) private var today
    /// The estimate whose amount editor is open, while it is.
    @State private var estimateBeingEntered: Transaction?

    var body: some View {
        let due = DebtsAndLoans(transactions).due(on: today)
        let estimatesDue = EstimatedAmounts(estimates).due(on: today)
        NavigationStack {
            List {
                ForEach(due) { loanOrDebt in
                    NavigationLink {
                        TransactionDetailView(transaction: loanOrDebt.original)
                    } label: {
                        LoanOrDebtRow(loanOrDebt: loanOrDebt, today: today)
                    }
                }
                ForEach(estimatesDue) { estimate in
                    Button {
                        estimateBeingEntered = estimate
                    } label: {
                        TransactionRow(transaction: estimate, showsDay: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if due.isEmpty && estimatesDue.isEmpty {
                    ContentUnavailableView(
                        "No Due Reminders",
                        systemImage: "bell",
                        description: Text("A Loan, Debt or estimated amount shows here once its reminder date comes.")
                    )
                }
            }
            .sheet(item: $estimateBeingEntered) { estimate in
                EstimatedAmountEditor(transaction: estimate)
            }
            .navigationTitle("Reminders")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 480)
        #endif
    }
}
