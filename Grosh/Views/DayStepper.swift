import SwiftUI

/// A form row for a transaction's date: a date picker between ‹ and › buttons that step one day back or forward.
/// `showsWeekday` writes the day of the week with the date, such as "Friday, Nov 13, 2026".
struct DayStepper: View {
    let title: LocalizedStringResource
    @Binding var day: CalendarDay
    var systemImage: String?
    var showsWeekday = false

    var body: some View {
        FormFieldRow(title: title, systemImage: systemImage) {
            HStack(spacing: 4) {
                Button {
                    day = day.adding(days: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel(Strings.Common.previousDay)

                dateControl
                    .frame(maxWidth: .infinity)

                Button {
                    day = day.adding(days: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel(Strings.Common.nextDay)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var dateControl: some View {
        if showsWeekday {
            let weekday = day.date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
            ZStack {
                DayPicker(title: title, day: $day)
                    .labelsHidden()
                    .opacity(0.011)
                    .accessibilityHidden(true)
                Text(weekday)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekday)
            .accessibilityAddTraits(.isButton)
        } else {
            DayPicker(title: title, day: $day)
                .labelsHidden()
        }
    }
}
