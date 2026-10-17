import Foundation
import SwiftData

/// What the Month graph reads from the store, so Home never reads every transaction: the transactions of the months a
/// month's graph spans, the forgiven Loans and Debts, and the first transaction that counts.
///
/// A month's graph sums what counts in the month itself, in the ``MonthGraphComparison/averageMonthCount`` months
/// before it (the Average) and in the same month last year (Last year). Everything else it needs is the first day
/// anything counts, where the strip starts and the Average counts months from.
enum MonthGraphHistory {
    /// The months the graph of `month` sums: Last year's month, then the Average's months and `month` itself, oldest
    /// first.
    static func months(for month: CalendarMonth) -> [CalendarMonth] {
        [month.adding(months: -12)]
            + (0...MonthGraphComparison.averageMonthCount).reversed().map { month.adding(months: -$0) }
    }

    /// The transactions dated in the ``months(for:)`` of `month`, outside Recently Deleted. A forgiven Loan or Debt
    /// counts on the day it was forgiven rather than its own, so it is left to ``forgiven``.
    static func transactions(for month: CalendarMonth) -> FetchDescriptor<Transaction> {
        let months = months(for: month)
        let lastYearFirst = months[0].firstDay.rawValue
        let lastYearLast = months[0].lastDay.rawValue
        let recentFirst = months[1].firstDay.rawValue
        let recentLast = month.lastDay.rawValue
        return FetchDescriptor(predicate: #Predicate { transaction in
            transaction.deletedAt == nil && transaction.forgivenCents == nil
                && (
                    (transaction.dayRaw >= lastYearFirst && transaction.dayRaw <= lastYearLast)
                        || (transaction.dayRaw >= recentFirst && transaction.dayRaw <= recentLast)
                )
        })
    }

    /// Every forgiven Loan and Debt outside Recently Deleted: what it forgave counts on the day it was forgiven,
    /// whatever its own day (ADR-0004). There are only ever a few.
    static var forgiven: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil && $0.forgivenCents != nil })
    }

    /// The earliest transaction that counts its own amount on the Month graph, as ``Transaction/countedAmount`` has it:
    /// outside Recently Deleted, paid from a wallet counted in the Total, counting in the report, and filed under an
    /// Expense or Income category that isn't a transfer half. A Loan or Debt is filed under a Debt/Loan category, so a
    /// forgiven one is never it: see ``firstDay(earliest:forgiven:)``.
    static var earliestCounted: FetchDescriptor<Transaction> {
        let expense: String? = CategoryType.expense.rawValue
        let income: String? = CategoryType.income.rawValue
        let outgoingTransfer: String? = LockedRole.outgoingTransfer.rawValue
        let incomingTransfer: String? = LockedRole.incomingTransfer.rawValue
        let inTotal = #Predicate<Transaction> { transaction in
            transaction.wallet?.isArchived == false && transaction.wallet?.includeInTotal == true
                && transaction.wallet?.deletedAt == nil
        }
        // The store compares a missing role with nothing, so a category without one is let through on its own.
        let notATransferHalf = #Predicate<Transaction> { transaction in
            transaction.category?.lockedRoleRaw == nil
                || (transaction.category?.lockedRoleRaw != outgoingTransfer
                    && transaction.category?.lockedRoleRaw != incomingTransfer)
        }
        let spentOrIncome = #Predicate<Transaction> { transaction in
            (transaction.category?.typeRaw == expense || transaction.category?.typeRaw == income)
                && notATransferHalf.evaluate(transaction)
        }
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                transaction.deletedAt == nil && !transaction.isExcludedFromReport
                    && inTotal.evaluate(transaction) && spentOrIncome.evaluate(transaction)
            },
            sortBy: [SortDescriptor(\.dayRaw)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// The first day anything counts on the Month graph, on either tab, or `nil` when nothing does: the earlier of the
    /// ``earliestCounted`` transaction's day and the day of the first forgiveness that counts.
    static func firstDay(earliest: [Transaction], forgiven: [Transaction]) -> CalendarDay? {
        (earliest + forgiven).compactMap(\.countedAmount).firstDay
    }
}
