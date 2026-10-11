import AppKit
import Testing
@testable import Grosh

@MainActor
struct ComingSoonTests {
    @Test func homeShowsReportThisMonthThenTopSpending() {
        #expect(ComingSoon.homeCards.map(\.title) == ["Report this month", "Top spending"])
    }

    @Test func budgetsIsNamedAsInTheSpec() {
        #expect(ComingSoon.budgets.title == "Budgets")
    }

    /// A misspelled SF Symbol name renders as a blank gap, which wouldn't look deliberate.
    @Test(arguments: ComingSoon.allCases)
    func everyPlaceholderShowsARealSymbol(_ placeholder: ComingSoon) {
        #expect(NSImage(systemSymbolName: placeholder.systemImage, accessibilityDescription: nil) != nil)
    }
}
