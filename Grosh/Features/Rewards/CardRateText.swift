import Foundation

/// How a Card's rates read.
enum CardRateText {
    /// `rate` (in percent) as "3%" or "1.5%".
    static func percent(_ rate: Double) -> String {
        (rate / 100).formatted(.percent.precision(.fractionLength(0...2)))
    }

    /// `value` as "3" or "1.25".
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The number typed in `text`, in the user's own way of writing one, or `nil` when it isn't one.
    static func parseNumber(_ text: String) -> Double? {
        try? Double(text.trimmingCharacters(in: .whitespaces), format: .number)
    }

    /// A catalog amount in US dollars, as "$2,500".
    static func dollars(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    /// A catalog `yyyy-MM-dd` day as the user's calendar writes a date, or the text as it is.
    static func day(_ isoDate: String) -> String {
        CalendarDay(isoDate: isoDate).map { $0.date().formatted(date: .abbreviated, time: .omitted) } ?? isoDate
    }
}
