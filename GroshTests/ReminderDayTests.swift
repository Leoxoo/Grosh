import Testing
@testable import Grosh

/// The rules every reminder day follows, a Loan's or Debt's and an Owes me's alike: when it is due, and how the open
/// ones are listed by it.
@Suite(.namedInTheLog)
struct ReminderDayTests {
    private let today = day(2026, 10, 12)

    @Test func aReminderIsDueFromItsDayOnAndNoReminderNeverIs() {
        #expect(ReminderDay.isDue(today, on: today))
        #expect(ReminderDay.isDue(today.adding(days: -1), on: today))
        #expect(!ReminderDay.isDue(today.adding(days: 1), on: today))
        #expect(!ReminderDay.isDue(nil, on: today))
    }

    @Test func aReminderDayIsListedBeforeNoneAndAnEarlierOneBeforeALaterOne() {
        let later = today.adding(days: 3)

        #expect(ReminderDay.isListed(today, before: later) { false })
        #expect(!ReminderDay.isListed(later, before: today) { true })
        #expect(ReminderDay.isListed(later, before: nil) { false })
        #expect(!ReminderDay.isListed(nil, before: today) { true })
    }

    @Test func theSameReminderDayOrNoneLeavesItToWhichIsOlder() {
        #expect(ReminderDay.isListed(today, before: today) { true })
        #expect(!ReminderDay.isListed(today, before: today) { false })
        #expect(ReminderDay.isListed(nil, before: nil) { true })
    }

    @Test func aReminderTurnedOnStartsAWeekLater() {
        #expect(ReminderDay.default(after: today) == day(2026, 10, 19))
    }
}
