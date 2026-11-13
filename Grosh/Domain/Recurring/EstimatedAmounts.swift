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

    /// "Amount to confirm", the notification's title.
    var title: String {
        String(localized: Strings.Recurring.amountToConfirm)
    }

    /// What was estimated, and that the real amount is to be entered.
    var body: String {
        String(localized: Strings.Recurring.estimatedAt(name, estimate.formatted()))
    }
}

/// Every Estimated transaction, which the Home bell and the reminders track until their real amounts are entered.
struct EstimatedAmounts: ReminderSource {
    /// The Estimated transactions, in no particular order.
    let open: [Transaction]

    /// Every Estimated transaction outside Recently Deleted. A new estimate, or a change to one, changes what this
    /// fetches.
    static var records: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.isEstimated && $0.deletedAt == nil })
    }

    init(_ transactions: some Sequence<Transaction>) {
        open = transactions.filter { $0.isEstimated && $0.deletedAt == nil }
    }

    static func reminderDay(of transaction: Transaction) -> CalendarDay? { transaction.estimateReminderDay }

    static func reminder(for transaction: Transaction, on day: CalendarDay) -> EstimateReminder {
        EstimateReminder(
            original: transaction.persistentModelID, day: day,
            name: transaction.recurring?.name ?? transaction.categoryName,
            estimate: Money(cents: abs(transaction.amountCents), currencyCode: transaction.amount.currencyCode)
        )
    }
}

/// What the amount editor of an Estimated transaction holds: its real amount, entered positive. It starts at the
/// estimate.
nonisolated struct EstimatedAmountDraft: AmountDraft, ValidatedDraft {
    var entry: AmountEntry
    let currencyCode: String

    init(confirming transaction: Transaction) {
        entry = AmountEntry(cents: abs(transaction.amountCents))
        currencyCode = transaction.amount.currencyCode
    }

    /// The real amount must be above zero.
    func validate() throws {
        guard amount.cents > 0 else { throw TransactionRuleError.missingAmount }
    }
}

extension Transaction {
    /// Confirms the amount of an Estimated transaction at the draft's, which must be above zero. It keeps its direction.
    /// Its Estimated mark, its reminder and so its bell item go with it. Saves.
    func confirmAmount(_ draft: EstimatedAmountDraft) throws {
        try draft.validate()
        amountCents = draft.amount.cents * (amountCents < 0 ? -1 : 1)
        clearEstimate()
        try saveToStore()
    }

    /// Clears the Estimated mark and its reminder, once the amount has been confirmed or edited.
    func clearEstimate() {
        isEstimated = false
        estimateReminderDay = nil
    }
}
