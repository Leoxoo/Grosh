import Foundation
import SwiftData

/// What an import from MoneyLover did.
struct MoneyLoverImportSummary: Equatable {}

/// Import from MoneyLover ("Replace all data"): a MoneyLover CSV export replaces every wallet, Card and transaction.
/// The categories are kept.
enum MoneyLoverImport {
    /// Replaces the wallets, Cards and transactions in `context` with those of `csv`, a MoneyLover export, entered
    /// at `now`. Saves.
    @discardableResult
    static func replaceAllData(
        with csv: String, in context: ModelContext, now: Date = .now
    ) throws -> MoneyLoverImportSummary {
        let rows = try MoneyLoverCSV.rows(in: csv)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let startingBalance = try context.lockedCategory(.startingBalance)
        try removeAllData(in: context)

        var wallets: [String: Wallet] = [:]
        for row in rows where wallets[row.walletName] == nil {
            let wallet = Wallet(name: row.walletName, sortOrder: wallets.count)
            context.insert(wallet)
            wallets[row.walletName] = wallet
            let firstDay = rows.filter { $0.walletName == row.walletName }.map(\.day).min() ?? row.day
            let starting = Transaction(amount: Money(cents: 0), day: firstDay, wallet: nil, category: nil)
            starting.isExcludedFromReport = true
            starting.createdAt = now.addingTimeInterval(-Double(rows.count + 1))
            context.insert(starting)
            starting.wallet = wallet
            starting.category = startingBalance
        }

        for (index, row) in rows.enumerated() {
            let transaction = Transaction(amount: row.amount, day: row.day, wallet: nil, category: nil, note: row.note)
            transaction.createdAt = now.addingTimeInterval(-Double(index))
            context.insert(transaction)
            transaction.wallet = wallets[row.walletName]
            transaction.category = categories.first { $0.name == row.categoryName }
        }
        try context.save()
        return MoneyLoverImportSummary()
    }

    /// Deletes every transaction, Card and wallet. Categories stay. Doesn't save.
    private static func removeAllData(in context: ModelContext) throws {
        for transaction in try context.fetch(FetchDescriptor<Transaction>()) {
            context.delete(transaction)
        }
        for card in try context.fetch(FetchDescriptor<Card>()) {
            context.delete(card)
        }
        for wallet in try context.fetch(FetchDescriptor<Wallet>()) {
            context.delete(wallet)
        }
    }
}
