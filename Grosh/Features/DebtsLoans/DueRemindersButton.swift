import SwiftUI

/// The Home bell itself: a plain bell while nothing is due, with a badge once a reminder is: a Loan's, a Debt's, an
/// Owes me's, or an estimated amount's.
struct DueRemindersButton: View {
    /// How many open Loans, Debts and Owes me have reached their reminder day, and estimated amounts their due day.
    let dueCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: dueCount == 0 ? "bell" : "bell.badge")
        }
        .accessibilityLabel(dueCount == 0 ? Text(Strings.Screens.reminders) : Text(Strings.DebtsLoans.dueReminders(dueCount)))
    }
}
