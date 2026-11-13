import Foundation

extension CalendarDay {
    /// The day as a row or a detail shows it, such as "Oct 12, 2026".
    var shortText: String {
        date().formatted(date: .abbreviated, time: .omitted)
    }

    /// A day of the month as people say it: "1st", "22nd", "31st".
    static func ordinal(_ dayOfMonth: Int) -> String {
        ordinalFormatter.string(from: dayOfMonth as NSNumber) ?? "\(dayOfMonth)"
    }

    /// Made once: a formatter is slow to make, and a picker of the days of the month asks for 31 at a time.
    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}
