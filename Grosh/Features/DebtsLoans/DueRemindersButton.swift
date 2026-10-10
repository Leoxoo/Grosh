import SwiftUI

/// The Home bell itself: a plain bell while nothing is due, with a badge once a Loan or Debt reminder is.
struct DueRemindersButton: View {
    /// How many open Loans and Debts have reached their reminder day.
    let dueCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: dueCount == 0 ? "bell" : "bell.badge")
        }
        .accessibilityLabel(dueCount == 0 ? Text("Reminders") : Text("\(dueCount) Due Reminders"))
    }
}
