import Foundation
import SwiftData

/// What Home's Month graph reads from the store, so Home never reads every transaction: the transactions of the months a
/// month's graph spans, the forgiven Loans and Debts, and the earliest transactions that may count.
///
/// A month's graph sums what counts in the month itself and in the months its comparisons read
/// (``MonthGraphComparison/monthsRead(for:)``). Everything else it needs is the first day anything counts, where the
/// strip starts and the Average counts months from.
///
/// Home reads these with `@Query` and puts them together with ``firstDay(earliest:forgiven:otherIncome:)`` and
/// ``history(read:forgiven:firstDay:wallets:otherIncome:)``. ``read(_:in:otherIncome:)`` does the same from a model
/// context, for tests and the benchmark, so they go through Home's own wiring.
enum MonthGraphHistory {
    /// The months the graph of `month` sums, oldest first: those its comparisons read, then `month` itself.
    static func months(for month: CalendarMonth) -> [CalendarMonth] {
        MonthGraphComparison.monthsRead(for: month) + [month]
    }

    /// The transactions dated in the ``months(for:)`` of `month`, outside Recently Deleted. A forgiven Loan or Debt
    /// counts on the day it was forgiven rather than its own, so it is left to ``forgiven``.
    static func transactions(for month: CalendarMonth) -> FetchDescriptor<Transaction> {
        // Last year's month, then a run of months up to `month`.
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

    /// How many of the earliest transactions ``earliestCounted`` reads.
    static let earliestCandidateCount = 10

    /// The earliest transactions that may count their own amount on the Month graph, earliest first. Every one
    /// ``Transaction/countedAmount(in:otherIncome:)`` counts in the Total passes, and every one the store can tell counts
    /// nothing is left out: it must be outside Recently Deleted, paid from a wallet counted in the Total, counting in the
    /// report, filed under an Expense or Income category that isn't a transfer half, and neither a payback the Total
    /// leaves out (``Transaction/isHiddenInTotal``) nor an Expense its Reimbursements cover exactly.
    ///
    /// The store can't add up what was paid back into other wallets (``Transaction/totalViewNetCents``), so an Expense
    /// with such paybacks passes, and counts nothing when they cover it exactly. That is why it reads a few, of which
    /// ``firstDay(earliest:forgiven:otherIncome:)`` takes the first that counts. A Loan or Debt is filed under a
    /// Debt/Loan category, so a forgiven one is never among them: see ``forgiven``.
    static var earliestCounted: FetchDescriptor<Transaction> {
        let expense: String? = CategoryType.expense.rawValue
        let income: String? = CategoryType.income.rawValue
        let outgoingTransfer: String? = LockedRole.outgoingTransfer.rawValue
        let incomingTransfer: String? = LockedRole.incomingTransfer.rawValue
        let reimbursement: String? = LockedRole.reimbursement.rawValue
        let inTotal = #Predicate<Transaction> { transaction in
            transaction.wallet?.isArchived == false && transaction.wallet?.includeInTotal == true
                && transaction.wallet?.deletedAt == nil
        }
        // The store compares a missing value with nothing, so a missing one is let through by a term of its own.
        let notATransferHalf = #Predicate<Transaction> { transaction in
            transaction.category?.lockedRoleRaw == nil
                || (transaction.category?.lockedRoleRaw != outgoingTransfer
                    && transaction.category?.lockedRoleRaw != incomingTransfer)
        }
        let spentOrIncome = #Predicate<Transaction> { transaction in
            (transaction.category?.typeRaw == expense || transaction.category?.typeRaw == income)
                && notATransferHalf.evaluate(transaction)
        }
        // `isHiddenInTotal` turned around: not a Reimbursement paying back an Expense outside Recently Deleted whose
        // wallet counts in the Total.
        let notAPayback = #Predicate<Transaction> { transaction in
            transaction.paidBackExpense == nil || transaction.category?.lockedRoleRaw == nil
                || transaction.category?.lockedRoleRaw != reimbursement
        }
        let expenseGoneOrWalletless = #Predicate<Transaction> { transaction in
            transaction.paidBackExpense?.deletedAt != nil || transaction.paidBackExpense?.wallet == nil
        }
        let expenseWalletLeftOut = #Predicate<Transaction> { transaction in
            transaction.paidBackExpense?.wallet?.isArchived == true
                || transaction.paidBackExpense?.wallet?.includeInTotal == false
        }
        let expenseWalletDeleted = #Predicate<Transaction> { transaction in
            transaction.paidBackExpense?.wallet?.deletedAt != nil
        }
        let expenseOutsideTotal = #Predicate<Transaction> { transaction in
            expenseGoneOrWalletless.evaluate(transaction) || expenseWalletLeftOut.evaluate(transaction)
                || expenseWalletDeleted.evaluate(transaction)
        }
        let notHiddenInTotal = #Predicate<Transaction> { transaction in
            notAPayback.evaluate(transaction) || expenseOutsideTotal.evaluate(transaction)
        }
        let notCoveredByItsReimbursements = #Predicate<Transaction> { transaction in
            transaction.category?.typeRaw != expense || transaction.amountCents >= 0
                || transaction.hasPaybacksElsewhere
                || transaction.amountCents + transaction.reimbursedCents != 0
        }
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { transaction in
                transaction.deletedAt == nil && !transaction.isExcludedFromReport
                    && inTotal.evaluate(transaction) && spentOrIncome.evaluate(transaction)
                    && notHiddenInTotal.evaluate(transaction) && notCoveredByItsReimbursements.evaluate(transaction)
            },
            sortBy: [SortDescriptor(\.dayRaw)]
        )
        descriptor.fetchLimit = earliestCandidateCount
        return descriptor
    }

    /// The first day anything counts on the Month graph, on either tab, or `nil` when nothing does: the earlier of the
    /// day of the first ``earliestCounted`` transaction that counts and the day of the first forgiveness that counts.
    static func firstDay(earliest: [Transaction], forgiven: [Transaction], otherIncome: Category) -> CalendarDay? {
        (earliest + forgiven).compactMap { $0.countedAmount(otherIncome: otherIncome) }.firstDay
    }

    /// The history Home draws a month's graph from: what counts in the Total among `read`, the month's
    /// ``transactions(for:)``, and `forgiven`, counting from `firstDay`, in the Total's currency among `wallets`, the
    /// unarchived wallets in the user's order (``WalletSelection/currencyCode(among:)``).
    static func history(
        read: [Transaction], forgiven: [Transaction], firstDay: CalendarDay?, wallets: [Wallet], otherIncome: Category
    ) -> CountedHistory {
        CountedHistory(
            read + forgiven, currencyCode: WalletSelection.total.currencyCode(among: wallets), otherIncome: otherIncome,
            firstDay: firstDay
        )
    }

    /// The history of `month`, read from `context` in one call as Home reads it through its queries: the same
    /// ``firstDay(earliest:forgiven:otherIncome:)`` and ``history(read:forgiven:firstDay:wallets:otherIncome:)`` over
    /// the same descriptors. Home itself never calls it; the tests and benchmarks read Home's history with it.
    static func read(_ month: CalendarMonth, in context: ModelContext, otherIncome: Category) throws -> CountedHistory {
        let forgiven = try context.fetch(Self.forgiven)
        let firstDay = firstDay(earliest: try context.fetch(earliestCounted), forgiven: forgiven, otherIncome: otherIncome)
        return history(
            read: try context.fetch(transactions(for: month)), forgiven: forgiven, firstDay: firstDay,
            wallets: try context.fetch(Wallet.unarchived), otherIncome: otherIncome
        )
    }
}
