import Foundation
import SwiftData

/// Import from MoneyLover ("Replace all data"): a MoneyLover CSV export replaces every wallet, Card and transaction.
/// The categories are kept.
enum MoneyLoverImport {
    /// Replaces the wallets, Cards and transactions in `context` with those of `csv`, a MoneyLover export, entered
    /// at `now`:
    ///
    /// - Each wallet is created once by name, with a $0 Starting balance on its first day.
    /// - Each row is filed under the category of its name; a name no category has becomes a new top-level category.
    /// - A card hashtag in a note becomes the row's Card (``MoneyLoverCardTag``), where the app would offer that Card:
    ///   not on a transfer row, and only in the Card's paying wallet. Elsewhere the hashtag stays in the note.
    /// - Outgoing and Incoming transfer rows link into transfers. One with no partner becomes a balance adjustment,
    ///   filed as Adjust Balance files it; one of no amount has nothing to adjust and isn't imported.
    /// - Each Debt Collection links to the earliest open Loan of its wallet and amount, each Repayment to a Debt.
    /// - Within a day, rows keep the file's order.
    ///
    /// Saves. Throws ``MoneyLoverImportError`` without changing anything when the file can't be read: the whole file,
    /// and the locked categories the import needs, are checked before anything is deleted. Should saving fail after
    /// that, the old wallets, Cards and transactions are gone already and importing the file again recovers.
    @discardableResult
    static func replaceAllData(
        with csv: String, in context: ModelContext, now: Date = .now
    ) throws -> MoneyLoverImportSummary {
        let rows = try MoneyLoverCSV.rows(in: csv)
        var importer = try Importer(rows: rows, context: context, now: now)
        do {
            try removeAllData(in: context)
            let summary = try importer.run()
            try context.save()
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Deletes every transaction, Card and wallet from the store. Categories stay. These are batch deletes: they take
    /// effect right away rather than at the next save, which makes replacing ~6,000 transactions about five times
    /// faster than deleting them one by one, but a rollback can't bring them back.
    private static func removeAllData(in context: ModelContext) throws {
        try context.delete(model: Transaction.self)
        try context.delete(model: Card.self)
        try context.delete(model: Wallet.self)
    }
}

/// One run of ``MoneyLoverImport/replaceAllData(with:in:now:)`` over rows already read, into a store already
/// emptied.
private struct Importer {
    let rows: [MoneyLoverRow]
    let context: ModelContext
    let now: Date
    /// The locked categories the import files under, fetched before anything is deleted.
    let startingBalance: Category
    /// What a transfer row with no partner is filed under as a balance adjustment, by the adjustment's reason type.
    let adjustmentReasons: [CategoryType: Category]

    private var wallets: [String: Wallet] = [:]
    private var walletOrder: [String] = []
    private var cards: [MoneyLoverCardTag: Card] = [:]

    init(rows: [MoneyLoverRow], context: ModelContext, now: Date) throws {
        self.rows = rows
        self.context = context
        self.now = now
        startingBalance = try context.lockedCategory(.startingBalance)
        adjustmentReasons = try [CategoryType.income, .expense].reduce(into: [:]) { reasons, type in
            reasons[type] = try BalanceAdjustmentDraft.defaultReason(for: type, in: context)
        }
    }

    /// Records every row, pairs the transfers, links the payments and says what was done. Doesn't save, except
    /// that linking a payment does.
    mutating func run() throws -> MoneyLoverImportSummary {
        var categories = try CategoryLookup(context: context)
        for row in rows where wallets[row.walletName] == nil {
            addWallet(firstSeenIn: row)
        }
        // `imported[i]` is `rows[i]`.
        var imported: [Transaction] = []
        for (index, row) in rows.enumerated() {
            let category = categories.category(named: row.categoryName, for: row.amount)
            imported.append(record(row, at: index, filedUnder: category))
        }

        var unmatched: [ObjectIdentifier: MoneyLoverImportSummary.UnmatchedRow.Outcome] = [:]
        for unpaired in Self.linkTransfers(among: imported) {
            // A balance adjustment records a difference, so a row of no amount has nothing to adjust.
            guard let type = BalanceAdjustmentDraft.reasonType(for: unpaired.amountCents) else {
                unmatched[ObjectIdentifier(unpaired)] = .notImported
                context.delete(unpaired)
                continue
            }
            unpaired.isBalanceAdjustment = true
            unpaired.category = adjustmentReasons[type]
            unmatched[ObjectIdentifier(unpaired)] = .balanceAdjustment
        }
        let kept = zip(rows, imported).filter { unmatched[ObjectIdentifier($1)] != .notImported }
        for unlinked in try Self.linkPayments(among: kept.map(\.1)) {
            unmatched[ObjectIdentifier(unlinked)] = .unlinkedPayment
        }

        return MoneyLoverImportSummary(
            wallets: walletOrder.map { name in
                .init(name: name, transactionCount: kept.count { row, _ in row.walletName == name })
            },
            cardsCreated: cards.count,
            unmatchedRows: zip(rows, imported).compactMap { row, transaction in
                unmatched[ObjectIdentifier(transaction)].map { outcome in
                    .init(
                        line: row.line, day: row.day, categoryName: row.categoryName, amount: row.amount,
                        walletName: row.walletName, outcome: outcome
                    )
                }
            }
        )
    }

    /// Creates the wallet `row` names, at the end of the order, with a $0 Starting balance on the earliest day any
    /// row of it is dated, entered before every row.
    private mutating func addWallet(firstSeenIn row: MoneyLoverRow) {
        let wallet = Wallet(name: row.walletName, sortOrder: walletOrder.count)
        context.insert(wallet)
        wallets[row.walletName] = wallet
        walletOrder.append(row.walletName)

        let firstDay = rows.filter { $0.walletName == row.walletName }.map(\.day).min() ?? row.day
        let starting = Transaction(amount: Money(cents: 0), day: firstDay, wallet: nil, category: nil)
        starting.isExcludedFromReport = true
        starting.createdAt = now.addingTimeInterval(-Double(rows.count + walletOrder.count))
        context.insert(starting)
        starting.wallet = wallet
        starting.category = startingBalance
    }

    /// Records `row`, the `index`th of the file. The file lists a day's rows newest first, so each row is entered a
    /// second before the one above it and they keep the file's order within a day.
    private mutating func record(_ row: MoneyLoverRow, at index: Int, filedUnder category: Category) -> Transaction {
        let wallet = wallets[row.walletName]
        let paid = paidWith(row, in: wallet, filedUnder: category)
        let note = paid.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let transaction = Transaction(amount: row.amount, day: row.day, wallet: nil, category: nil, note: note)
        transaction.createdAt = now.addingTimeInterval(-Double(index))
        transaction.withName = row.withName
        transaction.eventName = row.eventName
        transaction.isExcludedFromReport = row.isExcludedFromReport
        context.insert(transaction)
        transaction.wallet = wallet
        transaction.category = category
        transaction.card = paid.card
        return transaction
    }

    /// The Card `row` is paid with, and its note without that Card's hashtag. A row only gets a Card where the app
    /// would offer one (``TransactionDraft/offersCard``, ``Card/pickerChoices(for:keeping:)``): never on a transfer
    /// row, linked or not, and only in the Card's paying wallet. Elsewhere it gets no Card and its note stays as it
    /// is, hashtag included.
    private mutating func paidWith(
        _ row: MoneyLoverRow, in wallet: Wallet?, filedUnder category: Category
    ) -> (card: Card?, note: String) {
        guard !category.isTransferHalf, let wallet, let tagged = MoneyLoverCardTag.first(in: row.note),
              payingWallet(for: tagged.tag, firstOfferedIn: wallet) == wallet
        else { return (nil, row.note) }
        return (card(for: tagged.tag, paidFrom: wallet), tagged.note)
    }

    /// The wallet the Card `tag` names is paid from: Checking (Navy Federal), or when the file has no such wallet,
    /// `wallet`, that of the first row the Card is offered on.
    private func payingWallet(for tag: MoneyLoverCardTag, firstOfferedIn wallet: Wallet) -> Wallet {
        wallets[MoneyLoverCardTag.payingWalletName] ?? cards[tag]?.payingWallet ?? wallet
    }

    /// The Card `tag` names, created the first time a row is paid with it, so every Card has rows.
    private mutating func card(for tag: MoneyLoverCardTag, paidFrom wallet: Wallet) -> Card {
        if let card = cards[tag] { return card }
        let card = Card(
            name: tag.cardName, kind: tag.kind, payingWallet: nil, color: tag.color,
            sortOrder: MoneyLoverCardTag.all.firstIndex(of: tag) ?? cards.count
        )
        context.insert(card)
        card.payingWallet = wallet
        cards[tag] = card
        return card
    }

    /// Links the Outgoing and Incoming transfer rows among `imported` (in the file's order) into transfers: each
    /// Outgoing transfer with the first Incoming transfer not yet taken that is dated the same day, in another
    /// wallet, for the opposite amount. Returns the transfer rows left without a partner, in the file's order.
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
    /// first. Returns the payments left unlinked. Saves.
    private static func linkPayments(among imported: [Transaction]) throws -> [Transaction] {
        let oldestFirst = Array(imported.inListOrder().reversed())
        var open = oldestFirst.filter(\.isLoanOrDebt)
        var unlinked: [Transaction] = []
        for payment in oldestFirst {
            guard let role = payment.category?.lockedRole, role == .debtCollection || role == .repayment else {
                continue
            }
            guard let index = open.firstIndex(where: { original in
                original.loanOrDebtKind?.paymentRole == role && original.wallet == payment.wallet
                    && original.amountCents == -payment.amountCents && original.dayRaw <= payment.dayRaw
            }) else {
                unlinked.append(payment)
                continue
            }
            try open.remove(at: index).linkPayment(payment)
        }
        return unlinked
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
