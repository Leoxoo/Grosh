import Foundation
import SwiftData

/// A notification on the reminder day of an Estimated transaction, asking the user to enter its real amount.
nonisolated struct EstimateReminder: PendingReminder {
    static let identifierPrefix = "grosh.estimate-reminder."

    /// The Estimated transaction it reminds of.
    let original: PersistentIdentifier
    let day: CalendarDay
    /// The Recurring transaction's name, or its category's when it has none.
    let name: String
    /// The estimate the transaction holds, without its sign.
    let estimate: Money
    var arrival = ReminderArrival.onItsDay
}

/// Every Estimated transaction, which the Home bell and the reminders track until their real amounts are entered.
struct EstimatedAmounts: ReminderSource {
    /// The Estimated transactions, in no particular order.
    let open: [Transaction]

    /// Every Estimated transaction outside Recently Deleted. A new estimate, or a change to one, changes what this
    /// fetches.
    static var transactions: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.isEstimated && $0.deletedAt == nil })
    }

    static var records: FetchDescriptor<Transaction> { transactions }

    init(_ transactions: some Sequence<Transaction>) {
        open = transactions.filter { $0.isEstimated && $0.deletedAt == nil }
    }

    /// The Estimated transactions whose reminder day is `today` or earlier, the earliest first: what the Home bell
    /// lists.
    func due(on today: CalendarDay) -> [Transaction] {
        open.filter { $0.estimateReminderDay.map { $0 <= today } ?? false }
            .sorted { $0.estimateReminderDay ?? today < $1.estimateReminderDay ?? today }
    }

    /// The notifications that should be pending: one for each Estimated transaction whose reminder day is `today` or
    /// later, the soonest first. One whose day has passed is listed by the bell instead.
    func reminders(from today: CalendarDay) -> [EstimateReminder] {
        open.compactMap { transaction in
            guard let day = transaction.estimateReminderDay, day >= today else { return nil }
            return EstimateReminder(
                original: transaction.persistentModelID, day: day,
                name: transaction.recurring?.name ?? transaction.categoryName,
                estimate: Money(cents: abs(transaction.amountCents), currencyCode: transaction.amount.currencyCode)
            )
        }
        .sorted { $0.day < $1.day }
    }
}

extension Transaction {
    /// Confirms the amount of an Estimated transaction at `cents`, entered positive. It keeps its direction. Its
    /// Estimated mark, its reminder and so its bell item go with it. Saves.
    func confirmAmount(cents: Int) throws {
        amountCents = cents * (amountCents < 0 ? -1 : 1)
        clearEstimate()
        try modelContext?.save()
    }

    /// Clears the Estimated mark and its reminder, once the amount has been confirmed or edited.
    func clearEstimate() {
        isEstimated = false
        estimateReminderDay = nil
    }
}
