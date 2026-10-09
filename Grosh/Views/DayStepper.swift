import SwiftUI

/// A form row for a transaction's date: a date picker between ‹ and › buttons that step one day back or forward.
struct DayStepper: View {
    let title: LocalizedStringKey
    @Binding var day: CalendarDay

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Button {
                    day = day.adding(days: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel("Previous Day")

                DatePicker(title, selection: date, displayedComponents: .date)
                    .labelsHidden()

                Button {
                    day = day.adding(days: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel("Next Day")
            }
            .buttonStyle(.borderless)
        }
    }

    private var date: Binding<Date> {
        Binding(get: { day.date() }, set: { day = CalendarDay($0) })
    }
}
