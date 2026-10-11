import Foundation
import SwiftData

/// A schedule that makes a transaction on each of its due days: a name, an amount, a wallet, a category, how often it
/// repeats and when it ends. It is not a transaction and counts in no balance or report (ADR-0005).
@Model
final class RecurringTransaction {
    var name: String = ""
    /// The amount in cents, entered positive. The category's sign decides whether each transaction it makes adds to
    /// or takes from its wallet.
    var amountCents: Int = 0
    var note: String = ""
    /// The ``RecurringKind``'s raw value. A schedule starts with its category's default Kind and keeps it, whatever
    /// that default later becomes.
    var kindRaw: String = RecurringKind.regular.rawValue
    /// Whether a Bill's amount varies: each transaction it makes starts as an estimate, until the user enters the real
    /// amount. Only a Bill's does, see ``estimatesAmount``.
    var amountVaries: Bool = false
    /// For a varying Bill, how many days after an occurrence the user is reminded to enter its real amount.
    var remindAfterDays: Int = 2
    /// The first occurrence's ``CalendarDay`` as `yyyymmdd`.
    var startDayRaw: Int = 0
    /// The ``RepeatUnit``'s raw value.
    var repeatUnitRaw: String = RepeatUnit.month.rawValue
    /// How many units apart each occurrence falls.
    var repeatEvery: Int = 1
    /// The ``MonthlyDay``'s raw value: which day of the month a monthly repeat falls on.
    var monthlyDayRaw: String = MonthlyDay.sameDay.rawValue
    /// The ``RepeatEndKind``'s raw value, completed by ``untilDayRaw`` or ``occurrenceLimit`` where it needs them.
    var endKindRaw: String = RepeatEndKind.forever.rawValue
    /// The last day an occurrence may fall on, as `yyyymmdd`, for an end "until a date".
    var untilDayRaw: Int?
    /// How many occurrences in all, for an end "after N times".
    var occurrenceLimit: Int?
    /// The last due day that has been dealt with, as `yyyymmdd`: made into a transaction, or skipped when the schedule
    /// was saved. Occurrences up to and including it are never made again. `nil` before any has been dealt with.
    var handledThroughRaw: Int?
    var createdAt: Date = Date.now
    /// When the schedule was moved to Recently Deleted, or `nil` while it isn't there. It makes nothing while it is.
    var deletedAt: Date?
    /// Set on a schedule that went to Recently Deleted with its wallet, as part of that one item: it is restored with
    /// the wallet, never on its own.
    var deletedWithWallet: Bool = false
    /// A Subscription's cropped icon, as JPEG data (``SubscriptionIcon``). It is kept when the Kind changes, so changing
    /// back shows it again, but only ``subscriptionIcon`` shows it. External storage keeps the image out of the row.
    @Attribute(.externalStorage) var iconData: Data?

    var wallet: Wallet?
    var category: Category?
    var card: Card?

    /// The transactions this schedule made. Deleting the schedule leaves them as ordinary transactions.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurring)
    var transactions: [Transaction]? = []

    init() {}

    /// When the schedule repeats and ends. Changing it reshapes only the occurrences still to come.
    var schedule: RepeatSchedule {
        get {
            RepeatSchedule(
                start: CalendarDay(rawValue: startDayRaw),
                rule: RepeatRule(unit: RepeatUnit(rawValue: repeatUnitRaw) ?? .month, every: repeatEvery),
                end: end,
                monthlyDay: MonthlyDay(rawValue: monthlyDayRaw) ?? .sameDay
            )
        }
        set {
            startDayRaw = newValue.start.rawValue
            repeatUnitRaw = newValue.rule.unit.rawValue
            repeatEvery = newValue.rule.every
            monthlyDayRaw = newValue.monthlyDay.rawValue
            end = newValue.end
        }
    }

    /// When the schedule stops making occurrences.
    var end: RepeatEnd {
        get {
            switch RepeatEndKind(rawValue: endKindRaw) ?? .forever {
            case .forever: .forever
            case .until: .until(CalendarDay(rawValue: untilDayRaw ?? startDayRaw))
            case .afterCount: .afterCount(occurrenceLimit ?? 1)
            }
        }
        set {
            endKindRaw = newValue.kind.rawValue
            if case .until(let last) = newValue {
                untilDayRaw = last.rawValue
            } else {
                untilDayRaw = nil
            }
            if case .afterCount(let count) = newValue {
                occurrenceLimit = count
            } else {
                occurrenceLimit = nil
            }
        }
    }

    /// What sort of Recurring transaction it is, which the Recurring tab groups it by.
    var kind: RecurringKind {
        get { RecurringKind(rawValue: kindRaw) ?? .regular }
        set { kindRaw = newValue.rawValue }
    }

    /// The icon the Recurring transaction shows in place of its category's symbol: a Subscription's own, and none for any
    /// other Kind.
    var subscriptionIcon: Data? {
        kind == .subscription ? iconData : nil
    }

    /// Whether each transaction it makes starts Estimated: a Bill whose amount varies.
    var estimatesAmount: Bool { kind == .bill && amountVaries }

    /// The last due day dealt with, or `nil` before any has been.
    var handledThrough: CalendarDay? {
        get { handledThroughRaw.map { CalendarDay(rawValue: $0) } }
        set { handledThroughRaw = newValue?.rawValue }
    }

    /// The amount each transaction it makes is for, signed by its category, in its wallet's currency.
    var signedAmount: Money {
        Money(
            cents: amountCents * (category?.sign ?? -1),
            currencyCode: wallet?.currencyCode ?? Money.defaultCurrencyCode
        )
    }

    /// Whether the schedule is in Recently Deleted, on its own or with its wallet.
    var isInRecentlyDeleted: Bool { deletedAt != nil }

    /// Whether its wallet is archived. A paused schedule makes nothing until the wallet is unarchived.
    var isPaused: Bool { wallet?.isArchived == true }

    /// Whether the schedule makes transactions and shows Scheduled rows: it is neither deleted nor paused.
    var isActive: Bool { !isInRecentlyDeleted && !isPaused && wallet?.isInRecentlyDeleted != true }
}
