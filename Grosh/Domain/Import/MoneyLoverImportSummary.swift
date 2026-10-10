import Foundation

/// What an import from MoneyLover did, shown when it is done.
nonisolated struct MoneyLoverImportSummary: Equatable, Sendable {
    /// How many of the file's rows went into one wallet. Its Starting balance isn't counted.
    struct WalletCount: Equatable, Sendable {
        let name: String
        let transactionCount: Int
    }

    /// A row the import couldn't match with the row it belongs with.
    struct UnmatchedRow: Equatable, Sendable {
        /// What the import made of a row it couldn't match.
        enum Outcome: Equatable, Sendable {
            /// A transfer row with no partner, recorded as a balance adjustment.
            case balanceAdjustment
            /// A transfer row of no amount with no partner: as a balance adjustment it would have nothing to adjust,
            /// so it isn't imported.
            case notImported
            /// A Debt Collection or Repayment with no open Loan or Debt of its wallet and amount, recorded unlinked.
            case unlinkedPayment
        }

        /// The row as the file lists it.
        let row: MoneyLoverRow
        let outcome: Outcome
    }

    /// Every imported wallet, in the order the import created them.
    let wallets: [WalletCount]
    let cardsCreated: Int
    /// In the file's order.
    let unmatchedRows: [UnmatchedRow]

    /// Every row imported, across all wallets.
    var transactionCount: Int { wallets.reduce(0) { $0 + $1.transactionCount } }
}
