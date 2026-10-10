import SwiftData
import SwiftUI

extension View {
    /// Adds the Home bell to the toolbar: it shows whether any Loan or Debt reminder is due, and opens the list of due
    /// ones. Use inside the tab's `NavigationStack`.
    func dueRemindersBell() -> some View {
        modifier(DueRemindersBell())
    }
}

/// The bell and the sheet it opens. The sheet hangs off the screen rather than the toolbar button, so rebuilding the
/// toolbar never closes it.
private struct DueRemindersBell: ViewModifier {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @State private var isShowingList = false

    func body(content: Content) -> some View {
        let dueCount = DebtsAndLoans(transactions).due(on: .today).count
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

/// The open Loans and Debts whose reminder day has come, the earliest first. Each opens its transaction detail.
private struct DueRemindersList: View {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let today = CalendarDay.today
        let due = DebtsAndLoans(transactions).due(on: today)
        NavigationStack {
            List(due) { loanOrDebt in
                NavigationLink {
                    TransactionDetailView(transaction: loanOrDebt.original)
                } label: {
                    LoanOrDebtRow(loanOrDebt: loanOrDebt, today: today)
                }
            }
            .overlay {
                if due.isEmpty {
                    ContentUnavailableView(
                        "No Due Reminders",
                        systemImage: "bell",
                        description: Text("A Loan or Debt shows here once its reminder date comes.")
                    )
                }
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
