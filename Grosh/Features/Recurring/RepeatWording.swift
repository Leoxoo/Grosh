import Foundation
import SwiftUI

extension RepeatPreset {
    /// The preset's name in the Repeat picker.
    var title: LocalizedStringResource {
        switch self {
        case .daily: Strings.Recurring.daily
        case .weekly: Strings.Recurring.weekly
        case .biWeekly: Strings.Recurring.biWeekly
        case .monthly: Strings.Recurring.monthly
        case .yearly: Strings.Recurring.yearly
        case .custom: Strings.Common.custom
        }
    }
}

extension RepeatUnit {
    /// The unit's name in the Custom repeat's picker.
    var pluralTitle: LocalizedStringResource {
        switch self {
        case .day: Strings.Recurring.days
        case .week: Strings.Recurring.weeks
        case .month: Strings.Recurring.months
        case .year: Strings.Recurring.years
        }
    }
}

extension RepeatEndKind {
    /// The kind's name in the Ends picker.
    var title: LocalizedStringResource {
        switch self {
        case .forever: Strings.Recurring.never
        case .until: Strings.Recurring.onADate
        case .afterCount: Strings.Recurring.afterCount
        }
    }
}

extension RepeatRule {
    /// How often the rule repeats, before any day is named: "Every month", "Every 2 weeks".
    var phrase: String {
        switch unit {
        case .day: every == 1 ? String(localized: Strings.Recurring.everyDay) : String(localized: Strings.Recurring.everyDays(every))
        case .week: every == 1 ? String(localized: Strings.Recurring.everyWeek) : String(localized: Strings.Recurring.everyWeeks(every))
        case .month: every == 1 ? String(localized: Strings.Recurring.everyMonth) : String(localized: Strings.Recurring.everyMonths(every))
        case .year: every == 1 ? String(localized: Strings.Recurring.everyYear) : String(localized: Strings.Recurring.everyYears(every))
        }
    }
}

extension RepeatSchedule {
    /// How the repeat reads, with its day and its end: "Every 2 months on the 4th, until Dec 2027".
    var summary: String {
        var text = rule.phrase
        switch rule.unit {
        case .month:
            text += " " + monthlyDay.phrase(startingOn: start)
        case .year:
            text += " " + String(localized: Strings.Recurring.onDate(start.date().formatted(.dateTime.month(.abbreviated).day())))
        case .day, .week:
            break
        }
        switch end {
        case .forever:
            break
        case .until(let last):
            text += ", " + String(localized: Strings.Recurring.until(last.date().formatted(.dateTime.month(.abbreviated).year())))
        case .afterCount(let count):
            text += ", " + (count == 1 ? String(localized: Strings.Recurring.onceLowercase) : String(localized: Strings.Recurring.times(count)))
        }
        return text
    }
}

extension MonthlyDay {
    /// The day a monthly repeat names after "Every month": "on the 4th", "on the last Thursday", "on the last day".
    func phrase(startingOn start: CalendarDay) -> String {
        switch self {
        case .sameDay:
            return String(localized: Strings.Recurring.onThe(Self.ordinal(start.day)))
        case .nthWeekday:
            let weekday = start.date().formatted(.dateTime.weekday(.wide))
            switch (start.day - 1) / 7 {
            case 0: return String(localized: Strings.Recurring.onTheFirst(weekday))
            case 1: return String(localized: Strings.Recurring.onTheSecond(weekday))
            case 2: return String(localized: Strings.Recurring.onTheThird(weekday))
            case 3: return String(localized: Strings.Recurring.onTheFourth(weekday))
            default: return String(localized: Strings.Recurring.onTheLast(weekday))
            }
        case .lastDay:
            return String(localized: Strings.Recurring.onTheLastDay)
        }
    }

    /// A day of the month as an ordinal, such as "4th".
    private static func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
