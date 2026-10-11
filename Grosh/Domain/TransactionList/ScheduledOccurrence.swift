import Foundation

/// A Scheduled row: an occurrence of a Recurring transaction that is still to come, which Future lists beside its
/// transactions (ADR-0005). It is computed from the schedule and never stored. It is not a Transaction, so it counts in
/// no balance, Total, report or search result.
struct ScheduledOccurrence: Identifiable, Hashable {
    let recurring: RecurringTransaction
    /// The due day, after today.
    let day: CalendarDay

    var id: Self { self }

    /// Two occurrences are the same when they fall on the same day of the same schedule, which is compared by identity.
    static func == (lhs: ScheduledOccurrence, rhs: ScheduledOccurrence) -> Bool {
        lhs.recurring === rhs.recurring && lhs.day == rhs.day
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(recurring))
        hasher.combine(day)
    }

    /// What the occurrence will add to or take from its wallet, signed by its category.
    var amount: Money { recurring.signedAmount }

    /// Whether the transaction the occurrence makes starts Estimated: a Bill whose amount varies. Its row carries the
    /// Estimated mark too.
    var isEstimated: Bool { recurring.estimatesAmount }
}

extension RecurringTransaction {
    /// The days Future lists this schedule's Scheduled rows on, as seen from `today`: the next twelve after today that
    /// haven't been dealt with, and none beyond a year ahead. A schedule that isn't active lists none: one in Recently
    /// Deleted, one paused by an archived wallet, or one whose wallet is in Recently Deleted.
    func scheduledDays(today: CalendarDay) -> [CalendarDay] {
        guard isActive, let wallet, !wallet.isArchived, wallet.deletedAt == nil else { return [] }
        // Occurrences up to `handledThrough` are transactions already, or were skipped when the schedule was saved.
        let dealtWith = handledThrough.map { max($0, today) } ?? today
        return Array(schedule.occurrences(after: dealtWith, through: today.adding(days: 365)).prefix(12))
    }
}

extension Sequence where Element == RecurringTransaction {
    /// The Scheduled rows Future lists on `today` for the schedules paid from `selection`'s wallets: newest day first
    /// and, within a day, the most recently added schedule first, as the transactions on a day are listed.
    func scheduledOccurrences(selection: WalletSelection, today: CalendarDay) -> [ScheduledOccurrence] {
        filter { selection.includesWallet($0.wallet) }
            .flatMap { recurring in
                recurring.scheduledDays(today: today).map { ScheduledOccurrence(recurring: recurring, day: $0) }
            }
            .sorted { lhs, rhs in
                lhs.day == rhs.day ? lhs.recurring.createdAt > rhs.recurring.createdAt : lhs.day > rhs.day
            }
    }
}
