import Foundation

/// The unit a repeat counts in.
nonisolated enum RepeatUnit: String, CaseIterable, Sendable {
    case day, week, month, year
}

/// How often a schedule repeats: every `every` units of `unit`. A week is seven days.
nonisolated struct RepeatRule: Hashable, Sendable {
    var unit: RepeatUnit
    /// How many units apart each occurrence falls. Below 1 counts as 1.
    var every: Int
}

/// The repeats the form offers by name. ``custom`` takes its own unit and count.
nonisolated enum RepeatPreset: String, CaseIterable, Sendable {
    case daily, weekly, biWeekly, monthly, yearly, custom

    /// The rule the preset stands for, or `nil` for ``custom``.
    var rule: RepeatRule? {
        switch self {
        case .daily: RepeatRule(unit: .day, every: 1)
        case .weekly: RepeatRule(unit: .week, every: 1)
        case .biWeekly: RepeatRule(unit: .week, every: 2)
        case .monthly: RepeatRule(unit: .month, every: 1)
        case .yearly: RepeatRule(unit: .year, every: 1)
        case .custom: nil
        }
    }

    /// The preset a rule is shown as: the named one it matches, otherwise ``custom``.
    init(rule: RepeatRule) {
        self = Self.allCases.first { $0.rule == rule } ?? .custom
    }
}

/// When a schedule stops making occurrences.
nonisolated enum RepeatEnd: Hashable, Sendable {
    case forever
    /// The last day an occurrence may fall on. That day itself is included.
    case until(CalendarDay)
    /// How many occurrences in all, the first on the start day.
    case afterCount(Int)

    var kind: RepeatEndKind {
        switch self {
        case .forever: .forever
        case .until: .until
        case .afterCount: .afterCount
        }
    }
}

/// The kind of end the form offers. The end's date or count completes it.
nonisolated enum RepeatEndKind: String, CaseIterable, Sendable {
    case forever, until, afterCount
}

/// When a Recurring transaction falls due: from `start`, every `rule`, until `end`. Occurrences are computed, never
/// stored, so an edit reshapes the occurrences still to come and never the ones already made.
nonisolated struct RepeatSchedule: Hashable, Sendable {
    var start: CalendarDay
    var rule: RepeatRule
    var end: RepeatEnd

    /// The due day of occurrence `index`, counted from 0 for the start day, before the end is applied. Monthly and
    /// yearly occurrences keep the start day's number and fall back to a shorter month's last day. Each is counted
    /// from the start, so a schedule from January 31 falls on February 28, then March 31.
    func dueDay(ofOccurrence index: Int) -> CalendarDay {
        let steps = index * interval
        switch rule.unit {
        case .day:
            return start.adding(days: steps)
        case .week:
            return start.adding(days: steps * 7)
        case .month:
            let months = start.year * 12 + (start.month - 1) + steps
            return monthDay(year: months / 12, month: months % 12 + 1)
        case .year:
            return monthDay(year: start.year + steps, month: start.month)
        }
    }

    /// The due days after `previous` (every due day when `nil`), up to and including `through`, in order.
    func occurrences(after previous: CalendarDay?, through last: CalendarDay) -> [CalendarDay] {
        var due: [CalendarDay] = []
        var index = 0
        while true {
            let day = dueDay(ofOccurrence: index)
            guard day <= last, isWithinEnd(index: index, day: day) else { break }
            if previous.map({ day > $0 }) ?? true {
                due.append(day)
            }
            index += 1
        }
        return due
    }

    /// The first due day after `previous` (the start day when `nil`), or `nil` once the end has run out.
    func nextOccurrence(after previous: CalendarDay?) -> CalendarDay? {
        var index = 0
        while true {
            let day = dueDay(ofOccurrence: index)
            guard isWithinEnd(index: index, day: day) else { return nil }
            if previous.map({ day > $0 }) ?? true {
                return day
            }
            index += 1
        }
    }

    /// How many days `month` of `year` has, leap years included.
    static func daysInMonth(year: Int, month: Int) -> Int {
        let calendar = Calendar.utcGregorian
        let firstDay = CalendarDay(year: year, month: month, day: 1).date(in: calendar)
        return calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 28
    }

    /// A rule of zero or less would never move on, so it counts as one.
    private var interval: Int { max(1, rule.every) }

    private func monthDay(year: Int, month: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: min(start.day, Self.daysInMonth(year: year, month: month)))
    }

    private func isWithinEnd(index: Int, day: CalendarDay) -> Bool {
        switch end {
        case .forever: true
        case .until(let last): day <= last
        case .afterCount(let count): index < count
        }
    }
}
