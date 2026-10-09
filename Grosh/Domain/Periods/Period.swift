import Foundation

/// The span of time the transaction list is showing: a month by default, or Future.
///
/// No period but Future reaches past today: what is dated after today belongs to Future alone, so the
/// current month ends today.
nonisolated enum Period: Hashable, Sendable {
    case month(CalendarMonth)
    /// Every transaction dated after today.
    case future

    /// The days the period covers on `today`.
    func days(today: CalendarDay) -> DayRange {
        switch self {
        case .month(let month):
            DayRange(first: month.firstDay, last: min(month.lastDay, today))
        case .future:
            DayRange(first: today.adding(days: 1), last: nil)
        }
    }

    /// The period's name in the strip: "This month", "Last month", "08/2026", "Future".
    func title(today: CalendarDay) -> String {
        switch self {
        case .month(let month):
            let thisMonth = CalendarMonth(today)
            if month == thisMonth { return String(localized: "This month") }
            if month == thisMonth.adding(months: -1) { return String(localized: "Last month") }
            return String(format: "%02d/%d", month.month, month.year)
        case .future:
            return String(localized: "Future")
        }
    }
}
