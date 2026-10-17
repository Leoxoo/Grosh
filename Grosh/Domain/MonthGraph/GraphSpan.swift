import Foundation

/// The whole days a Month graph lays out across its width: one period of the strip, a month on Home and a day, week,
/// month, quarter or year on the Income and Spent details. Every day sits at the same share of the width whatever the
/// length of the span, so spans of different lengths line up.
struct GraphSpan: Equatable {
    /// The span's first day.
    let first: CalendarDay
    /// How many days the span has.
    let dayCount: Int
    /// The span's last day.
    let last: CalendarDay

    /// The span of a fixed period, or `nil` for All time, a custom range and Future, which have no fixed length.
    init?(_ period: Period) {
        switch period {
        case .day(let day):
            self.init(first: day, dayCount: 1)
        case .week(let startingOn):
            self.init(first: startingOn, dayCount: 7)
        case .month(let month):
            self.init(first: month.firstDay, dayCount: month.dayCount)
        case .quarter(let year, let quarter):
            let first = CalendarMonth(year: year, month: quarter * 3 - 2)
            let days = (0...2).reduce(0) { $0 + first.adding(months: $1).dayCount }
            self.init(first: first.firstDay, dayCount: days)
        case .year(let year):
            let days = (1...12).reduce(0) { $0 + CalendarMonth(year: year, month: $1).dayCount }
            self.init(first: CalendarDay(year: year, month: 1, day: 1), dayCount: days)
        case .all, .custom, .future:
            return nil
        }
    }

    init(first: CalendarDay, dayCount: Int) {
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
        let calendar = Calendar.utcGregorian
        let between = calendar.dateComponents([.day], from: first.date(in: calendar), to: day.date(in: calendar)).day ?? 0
        return between + 1
    }

    func contains(_ day: CalendarDay) -> Bool {
        day >= first && day <= last
    }
}

extension Period {
    /// The time range whose periods this period is one of: the range a strip of its length steps through, or `nil` for a
    /// period that isn't a fixed length.
    var timeRange: TimeRange? {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        case .all, .custom, .future: nil
        }
    }
}
