import Foundation
import SwiftData

/// What an import from MoneyLover did.
struct MoneyLoverImportSummary: Equatable {}

/// Import from MoneyLover ("Replace all data"): a MoneyLover CSV export replaces every wallet, Card and transaction.
/// The categories are kept.
enum MoneyLoverImport {
    /// Replaces the wallets, Cards and transactions in `context` with those of `csv`, a MoneyLover export, entered
    /// at `now`. Saves. Nothing changes when the file can't be imported.
    @discardableResult
    static func replaceAllData(
        with csv: String, in context: ModelContext, now: Date = .now
    ) throws -> MoneyLoverImportSummary {
        let rows = try MoneyLoverCSV.rows(in: csv)
        let startingBalance = try context.lockedCategory(.startingBalance)
        do {
            try removeAllData(in: context)
            var categories = try CategoryLookup(context: context)

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

            var cards: [MoneyLoverCardTag: Card] = [:]
            func card(for tag: MoneyLoverCardTag, firstUsedIn wallet: Wallet?) -> Card {
                if let card = cards[tag] { return card }
                let card = Card(
                    name: tag.cardName, kind: tag.kind,
                    payingWallet: nil, color: tag.color,
                    sortOrder: MoneyLoverCardTag.all.firstIndex(of: tag) ?? cards.count
                )
                context.insert(card)
                card.payingWallet = wallets[MoneyLoverCardTag.payingWalletName] ?? wallet
                cards[tag] = card
                return card
            }

            var imported: [Transaction] = []
            for (index, row) in rows.enumerated() {
                let wallet = wallets[row.walletName]
                let tagged = MoneyLoverCardTag.first(in: row.note)
                let note = (tagged?.note ?? row.note).trimmingCharacters(in: .whitespacesAndNewlines)
                let transaction = Transaction(amount: row.amount, day: row.day, wallet: nil, category: nil, note: note)
                transaction.createdAt = now.addingTimeInterval(-Double(index))
                transaction.withName = row.withName
                transaction.eventName = row.eventName
                transaction.isExcludedFromReport = row.isExcludedFromReport
                context.insert(transaction)
                transaction.wallet = wallet
                transaction.category = categories.category(named: row.categoryName, for: row.amount)
                transaction.card = tagged.map { card(for: $0.tag, firstUsedIn: wallet) }
                imported.append(transaction)
            }

            for unpaired in linkTransfers(among: imported) {
                unpaired.isBalanceAdjustment = true
                unpaired.category = try context.otherCategory(unpaired.amountCents < 0 ? .expense : .income)
            }
            try linkPayments(among: imported)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return MoneyLoverImportSummary()
    }

    /// Links the Outgoing and Incoming transfer rows among `imported` (in the file's order) into transfers: each
    /// Outgoing transfer with the first Incoming transfer not yet taken that is dated the same day, in another
    /// wallet, for the opposite amount. Returns the transfer rows left without a partner.
    private static func linkTransfers(among imported: [Transaction]) -> [Transaction] {
        struct Key: Hashable {
            let day: Int
            let cents: Int
        }
        var incoming = Dictionary(
            grouping: imported.filter { $0.category?.lockedRole == .incomingTransfer },
            by: { Key(day: $0.dayRaw, cents: $0.amountCents) }
        )
        for outgoing in imported where outgoing.category?.lockedRole == .outgoingTransfer {
            let key = Key(day: outgoing.dayRaw, cents: -outgoing.amountCents)
            guard let index = incoming[key]?.firstIndex(where: { $0.wallet != outgoing.wallet }),
                  let partner = incoming[key]?.remove(at: index)
            else { continue }
            let link = UUID()
            outgoing.linkID = link
            partner.linkID = link
        }
        return imported.filter { $0.category?.isTransferHalf == true && $0.linkID == nil }
    }

    /// Links each Debt Collection among `imported` to the earliest Loan still open that has its wallet and amount
    /// and is dated on or before it, and each Repayment to a Debt the same way (ADR-0003). Payments are taken oldest
    /// first. Saves.
    private static func linkPayments(among imported: [Transaction]) throws {
        let oldestFirst = Array(imported.inListOrder().reversed())
        var open = oldestFirst.filter(\.isLoanOrDebt)
        for payment in oldestFirst {
            guard let role = payment.category?.lockedRole, role == .debtCollection || role == .repayment,
                  let index = open.firstIndex(where: { original in
                      original.loanOrDebtKind?.paymentRole == role && original.wallet == payment.wallet
                          && original.amountCents == -payment.amountCents && original.dayRaw <= payment.dayRaw
                  })
            else { continue }
            try open.remove(at: index).linkPayment(payment)
        }
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

/// The category each imported row is filed under, found by name ignoring case. A name no category has becomes a new
/// top-level category, an Expense for money going out and an Income for money coming in.
private struct CategoryLookup {
    let context: ModelContext
    private var byName: [String: [Category]]

    init(context: ModelContext) throws {
        self.context = context
        byName = Dictionary(grouping: try context.fetch(FetchDescriptor<Category>()), by: { Self.key($0.name) })
    }

    private static func key(_ name: String) -> String { name.lowercased() }

    /// The category named `name` for a row of `amount`: when an Expense and an Income category share the name, the
    /// one of the type the amount's sign gives.
    mutating func category(named name: String, for amount: Money) -> Category {
        let type: CategoryType = amount.cents < 0 ? .expense : .income
        let named = byName[Self.key(name), default: []]
        if let match = named.first(where: { $0.type == type }) ?? named.first {
            return match
        }
        let topLevel = byName.values.joined().filter { $0.type == type && $0.parent == nil }
        let category = Category(
            name: name, type: type, symbolName: CategoryDraft().symbolName, color: CategoryDraft().color,
            sortOrder: (topLevel.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(category)
        byName[Self.key(name)] = [category]
        return category
    }
}
