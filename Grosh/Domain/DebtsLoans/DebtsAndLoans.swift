import Foundation
import SwiftData

/// Every Loan and Debt, split into the open ones (something still outstanding) and the settled ones, as Account →
/// Debts & Loans lists them.
struct DebtsAndLoans {
    /// Loans and Debts with something outstanding: those with a reminder (due) day first, the soonest first, then
    /// the rest, the oldest first.
    let open: [LoanOrDebt]
    /// Loans and Debts with nothing outstanding, the newest first.
    let settled: [LoanOrDebt]

    /// Every transaction filed under a Debt/Loan category: the Loans and Debts and their payments. A list made from
    /// them stays current, since a new payment or a change to a Loan or Debt changes what this fetches.
    static var transactions: FetchDescriptor<Transaction> {
        let debtLoan: String? = CategoryType.debtLoan.rawValue
        return FetchDescriptor(predicate: #Predicate { $0.category?.typeRaw == debtLoan })
    }

    /// The Loans and Debts among `transactions`, each with the payments among them that share its link.
    init(_ transactions: some Sequence<Transaction>) {
        let all = Array(transactions)
        let linked = Dictionary(grouping: all.filter { $0.linkID != nil }, by: \.linkID)
        let items = all.compactMap { transaction in
            LoanOrDebt(transaction, among: linked[transaction.linkID] ?? [])
        }
        open = items.filter { !$0.isSettled }.sorted { Self.isDue(before: $0, $1) }
        settled = items.filter(\.isSettled).sorted { $0.original.isListed(before: $1.original) }
    }

    /// Whether `first` comes before `second` among the open ones: a reminder day before none, an earlier reminder
    /// day before a later one, and otherwise the older Loan or Debt first.
    private static func isDue(before first: LoanOrDebt, _ second: LoanOrDebt) -> Bool {
        switch (first.original.reminderDay, second.original.reminderDay) {
        case let (firstDay?, secondDay?) where firstDay != secondDay: firstDay < secondDay
        case (.some, nil): true
        case (nil, .some): false
        default: second.original.isListed(before: first.original)
        }
    }

    /// Every Loan and Debt in the store.
    init(in context: ModelContext) throws {
        self.init(try context.fetch(Self.transactions))
    }
}
