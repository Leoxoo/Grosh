import SwiftUI

/// Picks the first and last day of a custom time range for the Transactions tab.
struct CustomRangeEditor: View {
    /// Called with the chosen days when the user taps Done.
    let choose: (DayRange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var first: CalendarDay
    @State private var last: CalendarDay

    /// Starts from `days`, or from today for an open end.
    init(days: DayRange, choose: @escaping (DayRange) -> Void) {
        self.choose = choose
        _first = State(initialValue: days.first ?? .today)
        _last = State(initialValue: days.last ?? .today)
    }

    var body: some View {
        NavigationStack {
            Form {
                DayPicker(title: "From", day: $first)
                DayPicker(title: "To", day: $last, earliest: first)
            }
            .navigationTitle("Custom Range")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        choose(days)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 160)
        #endif
    }

    /// The chosen days, earliest first whichever order the two pickers were set in.
    private var days: DayRange {
        DayRange(first: min(first, last), last: max(first, last))
    }
}
