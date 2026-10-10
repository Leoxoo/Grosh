import SwiftUI

/// Picks the first and last day of a custom time range for the Transactions tab.
struct CustomRangeEditor: View {
    /// Called with the chosen days when the user taps Done.
    let choose: (ClosedRange<CalendarDay>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var first: Date
    @State private var last: Date

    init(days: ClosedRange<CalendarDay>, choose: @escaping (ClosedRange<CalendarDay>) -> Void) {
        self.choose = choose
        _first = State(initialValue: days.lowerBound.date())
        _last = State(initialValue: days.upperBound.date())
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $first, displayedComponents: .date)
                DatePicker("To", selection: $last, in: first..., displayedComponents: .date)
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
    private var days: ClosedRange<CalendarDay> {
        let from = CalendarDay(first)
        let to = CalendarDay(last)
        return min(from, to)...max(from, to)
    }
}
