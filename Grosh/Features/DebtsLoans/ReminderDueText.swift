import SwiftUI

/// The reminder line of a Loan, Debt or Owes me row: a bell and the day it is due, in the urgent color once that day
/// has come.
struct ReminderDueText: View {
    let day: CalendarDay
    let isDue: Bool

    var body: some View {
        Text("\(Image(systemName: "bell")) \(Text(Strings.DebtsLoans.due(day.shortText)))")
            .font(.caption)
            .foregroundStyle(isDue ? .urgent : .secondary)
    }
}
