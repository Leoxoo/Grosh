import SwiftData

/// The Recurring transactions a screen shows what is still to come of, each with what its transactions start at now:
/// its signed amount, or a varying Bill's estimate (``RecurringTransaction/currentEstimateCents()``), read from the store
/// at most once here. A screen works them out once per save of the store (``StoreSaves``) rather than on each draw, since
/// an estimate takes a few fetches and Home's Month graph, Transactions → Future and the Income and Spent details draw
/// often. An estimate is read the first time it is asked for, so a month with nothing still due, such as one Home's
/// strip steps back to, reads none.
struct RecurringSchedules {
    let schedules: [RecurringTransaction]
    private let estimates = Estimates()

    init(_ schedules: [RecurringTransaction]) {
        self.schedules = schedules
    }

    /// No schedules: a graph with nothing due.
    static let none = RecurringSchedules([])

    /// What `recurring`'s transactions start at now (``RecurringTransaction/startingAmount(estimateCents:)``), with the
    /// estimate read for it here. Only schedules among ``schedules`` are asked about.
    func startingAmount(of recurring: RecurringTransaction) -> Money {
        recurring.startingAmount(estimateCents: estimates.cents(for: recurring))
    }

    /// The Scheduled rows Future lists on `today` for the schedules paid from `selection`'s wallets, or with `lastDay`,
    /// every occurrence still to come through it (see ``RecurringTransaction/scheduledDays(today:through:)``): newest
    /// day first and, within a day, the most recently added schedule first, as the transactions on a day are listed.
    /// Each carries its schedule's ``startingAmount(of:)``.
    func scheduledOccurrences(
        selection: WalletSelection, today: CalendarDay, through lastDay: CalendarDay? = nil
    ) -> [ScheduledOccurrence] {
        schedules.filter { selection.includesWallet($0.wallet) }
            .flatMap { recurring -> [ScheduledOccurrence] in
                let days = recurring.scheduledDays(today: today, through: lastDay)
                guard !days.isEmpty else { return [] }
                let amount = startingAmount(of: recurring)
                return days.map {
                    ScheduledOccurrence(recurring: recurring, day: $0, amount: amount)
                }
            }
            .sorted { lhs, rhs in
                lhs.day == rhs.day ? lhs.recurring.createdAt > rhs.recurring.createdAt : lhs.day > rhs.day
            }
    }

    /// The estimates read so far, kept with the schedules they were read for, so each is read once.
    private final class Estimates {
        private var read: [PersistentIdentifier: Int?] = [:]

        func cents(for recurring: RecurringTransaction) -> Int? {
            if let kept = read[recurring.persistentModelID] { return kept }
            let cents = recurring.currentEstimateCents()
            read[recurring.persistentModelID] = .some(cents)
            return cents
        }
    }
}
