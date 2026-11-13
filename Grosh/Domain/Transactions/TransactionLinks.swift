import Foundation
import SwiftData

nonisolated extension LinkKind {
    /// What a link made before link kinds were stored joins, worked out from `members`, the transactions on it
    /// (ADR-0012): a transfer half makes it a Transfer, a Loan, Debt or payment of one a Loan or Debt's, and a payback
    /// into another wallet or an Expense paid back that way a payback's. What is left, Expenses and Incomes on their own
    /// link, are the parts of a Split, as they were taken to be before. Also how an import tells what a Grosh export's
    /// links join.
    init(of members: some Sequence<Transaction>) {
        let members = Array(members)
        if members.contains(where: { $0.category?.isTransferHalf == true }) {
            self = .transfer
        } else if members.contains(where: { $0.isLoanOrDebt || $0.paidLoanOrDebtKind != nil }) {
            self = .loanOrDebt
        } else if members.contains(where: { $0.isFiledAsPayback || $0.hasPaybacksElsewhere }) {
            self = .payback
        } else {
            self = .split
        }
    }
}

extension Transaction {
    /// Brings a store made before link kinds were stored up to date, once, when it opens (ADR-0012): every link with
    /// no kind gets the one its transactions say (``LinkKind/init(of:)``), and an Expense still marked paid back into
    /// another wallet with none of those paybacks left is no longer marked, and leaves its link. Does nothing, past
    /// two narrow fetches, on a store already up to date. Saves when something changed.
    static func migrateLinkKinds(in context: ModelContext) throws {
        let unkinded = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.linkID != nil && $0.linkKindRaw == nil }
        ))
        if !unkinded.isEmpty {
            let links = Set(unkinded.compactMap(\.linkID))
            let linked = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkID != nil }))
            let byLink = Dictionary(grouping: linked.filter { $0.linkID.map(links.contains) == true }, by: \.linkID)
            for members in byLink.values {
                Transaction.link(members, as: LinkKind(of: members))
            }
        }
        let markedPaidBack = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.hasPaybacksElsewhere == true }
        ))
        for expense in markedPaidBack {
            expense.forgetPaybacks(removedForGood: [])
        }
        if context.hasChanges {
            try context.save()
        }
    }
}
