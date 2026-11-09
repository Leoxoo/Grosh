import SwiftUI

/// Picks the first and last day of a custom time range. The Transactions tab's may reach past today, to Future; the
/// Report's may not, so it passes the latest day it can pick.
struct CustomRangeEditor: View {
    /// Called with the chosen days when the user taps Done.
    let choose: (DayRange) -> Void
    /// The last day that can be picked, or `nil` for no limit.
    let latest: CalendarDay?

    @Environment(\.dismiss) private var dismiss
    @State private var first: CalendarDay
    @State private var last: CalendarDay

    /// Starts from `days`, or from `today` for an open end.
    init(days: DayRange, today: CalendarDay, latest: CalendarDay? = nil, choose: @escaping (DayRange) -> Void) {
        self.choose = choose
        self.latest = latest
        _first = State(initialValue: days.first ?? today)
        _last = State(initialValue: days.last ?? today)
    }

    var body: some View {
        NavigationStack {
            Form {
                DayPicker(title: Strings.Common.from, day: $first, latest: latest)
                DayPicker(title: Strings.Common.to, day: $last, earliest: first, latest: latest)
            }
            .navigationTitle(Strings.Transactions.customRange)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.done) {
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
