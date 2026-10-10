import SwiftUI

/// A date picker for a ``CalendarDay``, the one way a form picks a day from a calendar. ``DayStepper`` adds buttons
/// that step one day back or forward.
struct DayPicker: View {
    let title: LocalizedStringKey
    @Binding var day: CalendarDay
    /// When set, the first day that can be picked.
    var earliest: CalendarDay?

    var body: some View {
        if let earliest {
            DatePicker(title, selection: $day.date, in: earliest.date()..., displayedComponents: .date)
        } else {
            DatePicker(title, selection: $day.date, displayedComponents: .date)
        }
    }
}

extension Binding where Value == CalendarDay {
    /// The day as the `Date` a `DatePicker` takes: the start of the day on the user's calendar.
    var date: Binding<Date> {
        Binding<Date>(get: { wrappedValue.date() }, set: { wrappedValue = CalendarDay($0) })
    }
}
