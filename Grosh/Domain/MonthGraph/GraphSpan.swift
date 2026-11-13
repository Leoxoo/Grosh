import Foundation

/// The whole days a Month graph lays out across its width: one period of the strip, a month on Home and a week, month,
/// quarter or year on the Income and Spent details. Every day sits at the same share of the width whatever the length
/// of the span, so spans of different lengths line up.
struct GraphSpan: Equatable {
    /// What kind of period the span is.
    enum Length: Equatable {
        case week
        case month
        case quarter
        case year
    }

    let length: Length
    let first: CalendarDay
    let dayCount: Int
    let last: CalendarDay

    /// The span of a week, month, quarter or year, or `nil` for any other period: a day is too short to draw a line
    /// across, and All time, a custom range and Future have no fixed length.
    init?(_ period: Period) {
        switch period {
        case .week(let startingOn):
            self.init(.week, first: startingOn, dayCount: 7)
        case .month(let month):
            self.init(.month, first: month.firstDay, dayCount: month.dayCount)
        case .quarter(let year, let quarter):
            let first = CalendarMonth(year: year, month: quarter * 3 - 2)
            let days = (0...2).reduce(0) { $0 + first.adding(months: $1).dayCount }
            self.init(.quarter, first: first.firstDay, dayCount: days)
        case .year(let year):
            let days = (1...12).reduce(0) { $0 + CalendarMonth(year: year, month: $1).dayCount }
            self.init(.year, first: CalendarDay(year: year, month: 1, day: 1), dayCount: days)
        case .day, .all, .custom, .future:
            return nil
        }
    }

    private init(_ length: Length, first: CalendarDay, dayCount: Int) {
        self.length = length
        self.first = first
        self.dayCount = dayCount
        self.last = first.adding(days: dayCount - 1)
    }

    /// Day `number` of the span, 1 for its first day up to `dayCount` for its last.
    func day(_ number: Int) -> CalendarDay {
        first.adding(days: number - 1)
    }

    /// Which day of the span `day` is, 1 for the first, or `0` when it falls before the span.
    func number(of day: CalendarDay) -> Int {
        DayRange(first: first, last: day).dayCount ?? 0
    }

    func contains(_ day: CalendarDay) -> Bool {
        day >= first && day <= last
    }
}
