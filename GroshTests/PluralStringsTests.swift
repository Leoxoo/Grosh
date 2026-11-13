import Foundation
import Testing
@testable import Grosh

@Suite(.namedInTheLog)
struct PluralStringsTests {
    /// A count takes its singular from the String Catalog's plural forms, not from a second "1 …" string.
    @Test func oneTakesTheSingular() {
        #expect(String(localized: Strings.RecentlyDeleted.transactionCount(1)) == "1 transaction")
        #expect(String(localized: Strings.RecentlyDeleted.daysLeft(1)) == "1 day left")
        #expect(String(localized: Strings.Recurring.remindDaysLater(1)) == "Remind me 1 day later")
    }

    @Test func moreThanOneTakesThePlural() {
        #expect(String(localized: Strings.RecentlyDeleted.transactionCount(3)) == "3 transactions")
        #expect(String(localized: Strings.RecentlyDeleted.daysLeft(30)) == "30 days left")
        #expect(String(localized: Strings.Recurring.remindDaysLater(2)) == "Remind me 2 days later")
    }
}
