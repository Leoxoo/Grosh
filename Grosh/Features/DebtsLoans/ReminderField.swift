import SwiftUI

/// A Loan's or Debt's reminder: a switch, and once it is on, the day a notification arrives. Turning it on asks to
/// send notifications, which the system only shows the first time. Use inside a `Form` or `List`.
struct ReminderField: View {
    @Binding var day: CalendarDay?

    var body: some View {
        Toggle("Reminder", systemImage: "bell", isOn: isOn)
        if let day {
            DatePicker(
                "Remind Me On",
                selection: Binding(get: { day.date() }, set: { self.day = CalendarDay($0) }),
                displayedComponents: .date
            )
        }
    }

    private var isOn: Binding<Bool> {
        Binding {
            day != nil
        } set: { isOn in
            day = isOn ? TransactionDefaults.reminderDay(from: .today) : nil
            if isOn {
                Task { _ = await LocalNotificationReminders().requestPermission() }
            }
        }
    }
}
