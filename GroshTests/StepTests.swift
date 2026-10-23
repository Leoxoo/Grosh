import Foundation
import Testing
@testable import Grosh

/// How a Net income or Trend screen splits its span into Steps, and how each Step is named.
@MainActor
struct StepTests {
    /// Weeks start on Monday, as `Calendar.firstWeekday` numbers it (2 is Monday), so the tests don't depend on the
    /// device's locale.
    private let monday = 2
    private let english = Locale(identifier: "en_US")

    private func titles(_ steps: [Step]) -> [String] {
        steps.map { $0.title(locale: english) }
    }

    // MARK: The Steps of each time range

    @Test func aDayIsOneStepOfItself() {
        let steps = Step.steps(
            for: .day, over: DayRange(first: day(2026, 10, 16), last: day(2026, 10, 16)), today: day(2026, 10, 16)
        )
        #expect(titles(steps) == ["10/16/2026"])
    }

    @Test func aWeekIsItsDays() {
        let steps = Step.steps(
            for: .week, over: DayRange(first: day(2026, 10, 12), last: day(2026, 10, 18)), today: day(2026, 10, 16),
            firstWeekday: monday
        )
        #expect(steps.map(\.first) == (12...16).map { day(2026, 10, $0) })
        #expect(steps.allSatisfy { $0.unit == .day })
    }

    /// The ticket's example: this month on Oct 16, with weeks starting Monday, gives 1–4, 5–11 and 12–16, each cut at the
    /// month's edges and at today.
    @Test func aMonthIsItsWeeksCutAtTheMonthsEdgesAndToday() {
        let steps = Step.steps(
            for: .month, over: DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31)), today: day(2026, 10, 16),
            firstWeekday: monday
        )
        #expect(titles(steps) == ["1–4", "5–11", "12–16"])
        #expect(steps.allSatisfy { $0.unit == .week })
    }

    /// A week that crosses a month's edge can't be named by the days of one month, so it is named in numbers.
    @Test func aWeekThatCrossesAMonthIsNamedInNumbers() {
        let span = DayRange(first: day(2026, 10, 20), last: day(2026, 12, 31))
        let steps = Step.steps(for: .custom(span), over: span, today: day(2026, 12, 31), firstWeekday: monday)
        #expect(titles(steps) == [
            "20–25", "10/26 – 11/01/2026", "2–8", "9–15", "16–22", "23–29", "11/30 – 12/06/2026", "7–13",
            "14–20", "21–27", "28–31",
        ])
        #expect(steps.allSatisfy { $0.unit == .week })
    }

    @Test func aQuarterIsItsMonths() {
        let steps = Step.steps(
            for: .quarter, over: DayRange(first: day(2026, 7, 1), last: day(2026, 9, 30)), today: day(2026, 10, 16)
        )
        #expect(titles(steps) == ["07/2026", "08/2026", "09/2026"])
        #expect(steps.allSatisfy { $0.unit == .month })
    }

    /// A year's months stop at today, so the current month is cut short.
    @Test func aYearIsItsMonthsCutAtToday() {
        let steps = Step.steps(
            for: .year, over: DayRange(first: day(2026, 1, 1), last: day(2026, 12, 31)), today: day(2026, 10, 16)
        )
        #expect(titles(steps) == (1...10).map { String(format: "%02d/2026", $0) })
        #expect(steps.last?.last == day(2026, 10, 16))
    }

    // MARK: Custom ranges and All time, by length

    /// A custom range of 03/07/2025–10/16/2026, about 19 months, gives quarters: the first cut at its start and the last at
    /// today.
    @Test func aCustomRangeOfNineteenMonthsGivesQuarters() {
        let span = DayRange(first: day(2025, 3, 7), last: day(2026, 10, 16))
        let steps = Step.steps(for: .custom(span), over: span, today: day(2026, 10, 16))
        #expect(titles(steps) == ["Q1/2025", "Q2/2025", "Q3/2025", "Q4/2025", "Q1/2026", "Q2/2026", "Q3/2026", "Q4/2026"])
        #expect(steps.first?.first == day(2025, 3, 7))
        #expect(steps.last?.last == day(2026, 10, 16))
    }

    /// Tapping Q3/2025 opens July–September 2025 alone, and that span is three months, so it is split into months.
    @Test func aQuarterSplitsIntoItsThreeMonths() {
        let span = DayRange(first: day(2025, 7, 1), last: day(2025, 9, 30))
        let steps = Step.steps(for: .custom(span), over: span, today: day(2026, 10, 16))
        #expect(titles(steps) == ["07/2025", "08/2025", "09/2025"])
    }

    @Test func aFourYearAllTimeGivesYears() {
        let span = DayRange(first: day(2022, 6, 1), last: day(2026, 10, 16))
        let steps = Step.steps(for: .all, over: span, today: day(2026, 10, 16))
        #expect(titles(steps) == ["2022", "2023", "2024", "2025", "2026"])
        #expect(steps.allSatisfy { $0.unit == .year })
    }

    /// The length rule: days for up to 31 days, weeks for under 3 months, months for up to 12 months, quarters for up to 3
    /// years, and years beyond that.
    @Test func theLengthRuleChangesAtEachLimit() {
        #expect(Step.unit(for: DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31))) == .day)
        #expect(Step.unit(for: DayRange(first: day(2026, 10, 1), last: day(2026, 11, 1))) == .week)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2026, 3, 30))) == .week)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2026, 3, 31))) == .month)
        #expect(Step.unit(for: DayRange(first: day(2026, 7, 1), last: day(2026, 9, 30))) == .month)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2026, 12, 30))) == .month)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2026, 12, 31))) == .month)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2027, 1, 1))) == .quarter)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2028, 12, 31))) == .quarter)
        #expect(Step.unit(for: DayRange(first: day(2026, 1, 1), last: day(2029, 1, 1))) == .year)
    }

    // MARK: Coverage

    /// The Steps cover the span exactly, one after another, with no day left out or counted twice.
    @Test func theStepsCoverTheSpanOnceEach() {
        let span = DayRange(first: day(2025, 3, 7), last: day(2026, 10, 16))
        let steps = Step.steps(for: .custom(span), over: span, today: day(2026, 10, 16))
        #expect(steps.first?.first == span.first)
        #expect(steps.last?.last == span.last)
        for (earlier, later) in zip(steps, steps.dropFirst()) {
            #expect(later.first == earlier.last.adding(days: 1))
        }
    }

    /// A Step is never cut past today, even when the span reaches beyond it.
    @Test func noStepReachesPastToday() {
        let span = DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31))
        let steps = Step.steps(for: .month, over: span, today: day(2026, 10, 16), firstWeekday: monday)
        #expect(steps.allSatisfy { $0.last <= day(2026, 10, 16) })
    }
}
