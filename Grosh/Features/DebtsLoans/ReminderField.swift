import SwiftUI

/// A Loan's, Debt's or Owes me's reminder: a switch, and once it is on, the day a notification arrives. Once the first
/// reminder is saved, the app asks to send notifications (``SwiftUI/View/syncsDebtReminders()`` and
/// ``SwiftUI/View/syncsExpectedReimbursementReminders()``) and schedules it as soon as the user allows them. Use inside
/// a `Form` or `List`.
struct ReminderField: View {
    @Binding var day: CalendarDay?
    /// The day switching the reminder on counts a week from (``ReminderDay/default(after:)``): today for a Loan or Debt,
    /// which passes `nil`; an Owes me passes its Expense's day.
    var countingFrom: CalendarDay?

    @Environment(\.today) private var today

    var body: some View {
        Toggle(Strings.DebtsLoans.reminder, systemImage: "bell", isOn: isOn)
        if let day = Binding($day) {
            DayPicker(title: Strings.DebtsLoans.remindMeOn, day: day)
        }
    }

    private var isOn: Binding<Bool> {
        Binding {
            day != nil
        } set: { isOn in
            day = isOn ? ReminderDay.default(after: countingFrom ?? today) : nil
        }
    }
}
