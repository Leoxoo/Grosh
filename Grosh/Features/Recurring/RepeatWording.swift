import Foundation
import SwiftUI

extension RepeatPreset {
    /// The preset's name in the Repeat picker.
    var title: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biWeekly: "Bi-weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .custom: "Custom"
        }
    }
}

extension RepeatUnit {
    /// The unit's name in the Custom repeat's picker.
    var pluralTitle: LocalizedStringKey {
        switch self {
        case .day: "Days"
        case .week: "Weeks"
        case .month: "Months"
        case .year: "Years"
        }
    }
}

extension RepeatEndKind {
    /// The kind's name in the Ends picker.
    var title: LocalizedStringKey {
        switch self {
        case .forever: "Never"
        case .until: "On a date"
        case .afterCount: "After a number of times"
        }
    }
}

extension RepeatRule {
    /// How often the rule repeats, before any day is named: "Every month", "Every 2 weeks".
    var phrase: String {
        switch unit {
        case .day: every == 1 ? String(localized: "Every day") : String(localized: "Every \(every) days")
        case .week: every == 1 ? String(localized: "Every week") : String(localized: "Every \(every) weeks")
        case .month: every == 1 ? String(localized: "Every month") : String(localized: "Every \(every) months")
        case .year: every == 1 ? String(localized: "Every year") : String(localized: "Every \(every) years")
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
            text += " " + String(localized: "on \(start.date().formatted(.dateTime.month(.abbreviated).day()))")
        case .day, .week:
            break
        }
        switch end {
        case .forever:
            break
        case .until(let last):
            text += ", " + String(localized: "until \(last.date().formatted(.dateTime.month(.abbreviated).year()))")
        case .afterCount(let count):
            text += ", " + (count == 1 ? String(localized: "once") : String(localized: "\(count) times"))
        }
        return text
    }
}

extension MonthlyDay {
    /// The day a monthly repeat names after "Every month": "on the 4th", "on the last Thursday", "on the last day".
    func phrase(startingOn start: CalendarDay) -> String {
        switch self {
        case .sameDay:
            return String(localized: "on the \(Self.ordinal(start.day))")
        case .nthWeekday:
            let weekday = start.date().formatted(.dateTime.weekday(.wide))
            switch (start.day - 1) / 7 {
            case 0: return String(localized: "on the first \(weekday)")
            case 1: return String(localized: "on the second \(weekday)")
            case 2: return String(localized: "on the third \(weekday)")
            case 3: return String(localized: "on the fourth \(weekday)")
            default: return String(localized: "on the last \(weekday)")
            }
        case .lastDay:
            return String(localized: "on the last day")
        }
    }

    /// A day of the month as an ordinal, such as "4th".
    private static func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
