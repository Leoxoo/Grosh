import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Grosh

/// The day screens treat as today, which they read from the SwiftUI environment so a screen can be shown as of a fixed
/// day.
@MainActor
@Suite(.namedInTheLog)
struct TodayEnvironmentTests {
    @Test func theDefaultIsTheRealToday() {
        let before = CalendarDay.today
        let value = EnvironmentValues().today
        let after = CalendarDay.today

        // A run that crosses midnight may see either day.
        #expect(value == before || value == after)
    }

    @Test func aDaySetOnTheEnvironmentReadsBack() {
        var values = EnvironmentValues()
        values.today = day(2026, 10, 9)

        #expect(values.today == day(2026, 10, 9))
    }

    /// A period reaching past today ends in a Projected balance, any other in an Ending balance. A custom range of
    /// October 2026 reaches past a day inside it and not past a day after it, so the summary reads differently on the
    /// two, whatever the real date is.
    @Test func aScreenShowsAsOfTheDayItIsGiven() throws {
        let october = Period.custom(DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31)))

        let inside = try pixels(of: october, shownOn: day(2026, 10, 9))
        let after = try pixels(of: october, shownOn: day(2026, 11, 2))

        #expect(inside != after)
        #expect(try pixels(of: october, shownOn: day(2026, 10, 9)) == inside)
        #expect(try pixels(of: october, shownOn: day(2026, 11, 2)) == after)
    }

    /// The Transactions tab's period summary for `period`, drawn as it is on `today`.
    private func pixels(of period: Period, shownOn today: CalendarDay) throws -> Data {
        let summary = PeriodSummary(openingBalance: Money(cents: 100_00), endingBalance: Money(cents: 57_50))
        let screen = PeriodSummaryView(summary: summary, period: period)
            .environment(\.today, today)
            .frame(width: 390)
        let renderer = ImageRenderer(content: screen)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let data = try #require(image.dataProvider?.data)
        return data as Data
    }
}
