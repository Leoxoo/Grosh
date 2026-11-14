#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Testing
@testable import Grosh

@MainActor
@Suite(.namedInTheLog)
struct ComingSoonTests {
    /// The Spent and Income cards took Report this month's place, so Top spending is all Home still waits for.
    @Test func homeShowsOnlyTopSpending() {
        #expect(ComingSoon.homeCards.map(\.title) == ["Top spending"])
    }

    @Test func budgetsIsNamedAsInTheSpec() {
        #expect(ComingSoon.budgets.title == "Budgets")
    }

    /// A misspelled SF Symbol name renders as a blank gap, which wouldn't look deliberate.
    @Test(arguments: ComingSoon.allCases)
    func everyPlaceholderShowsARealSymbol(_ placeholder: ComingSoon) {
        #if os(macOS)
        #expect(NSImage(systemSymbolName: placeholder.systemImage, accessibilityDescription: nil) != nil)
        #else
        #expect(UIImage(systemName: placeholder.systemImage) != nil)
        #endif
    }
}
