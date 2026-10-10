import Foundation
import SwiftData

/// Import from MoneyLover ("Replace all data"): a MoneyLover CSV export replaces every wallet, Card and transaction.
/// The categories are kept.
enum MoneyLoverImport {
    /// Replaces the wallets, Cards and transactions in `context` with `rows`, a MoneyLover export as
    /// ``MoneyLoverCSV/rows(in:)`` reads it, entered at `now`:
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
    /// Saves once, at the end: the old data is deleted by the same save that adds the new. Throws without changing
    /// anything when it can't finish, saving included, and ``MoneyLoverImportError/noTransactions`` for no rows.
    /// Once saved, the old data can't be brought back.
    @discardableResult
    static func replaceAllData(
        with rows: [MoneyLoverRow], in context: ModelContext, now: Date = .now
    ) throws -> MoneyLoverImportSummary {
        guard !rows.isEmpty else { throw MoneyLoverImportError.noTransactions }
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

    /// Deletes every transaction, Card and wallet. Categories stay. Doesn't save. One by one, rather than as batch
    /// deletes, which would be faster but take effect in the store right away, where a rollback can't undo them.
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

/// One run of ``MoneyLoverImport/replaceAllData(with:in:now:)``, after the old data is deleted.
private struct Importer {
    let rows: [MoneyLoverRow]
    let context: ModelContext
    let now: Date
    /// What a transfer row with no partner is filed under as a balance adjustment, by the adjustment's reason type.
    let adjustmentReasons: [CategoryType: Category]

    private var wallets: [String: Wallet] = [:]
    private var walletOrder: [String] = []
    private var cards: [MoneyLoverCardTag: Card] = [:]

    init(rows: [MoneyLoverRow], context: ModelContext, now: Date) throws {
        self.rows = rows
        self.context = context
        self.now = now
        adjustmentReasons = try [CategoryType.income, .expense].reduce(into: [:]) { reasons, type in
            reasons[type] = try BalanceAdjustmentDraft.defaultReason(for: type, in: context)
        }
    }

    /// Records every row, links the transfers and the payments, and says what was done. Doesn't save.
    mutating func run() throws -> MoneyLoverImportSummary {
        for row in rows where wallets[row.walletName] == nil {
            try addWallet(firstSeenIn: row)
        }
        var categories = try CategoryFiler(context: context)
        let filed = try rows.map { try categories.findOrAdd(named: $0.categoryName, for: $0.amount) }
        let paid = try addCards(for: filed)
        // `imported[i]` is `rows[i]`.
        let imported = rows.indices.map { index in
            record(rows[index], at: index, filedUnder: filed[index], paidWith: paid[index].card, note: paid[index].note)
        }

        var unmatched: [ObjectIdentifier: MoneyLoverImportSummary.UnmatchedRow.Outcome] = [:]
        for unlinked in Self.linkTransfers(among: imported) {
            // A balance adjustment records a difference, so a row of no amount has nothing to adjust.
            guard let type = BalanceAdjustmentDraft.reasonType(for: unlinked.amountCents) else {
                unmatched[ObjectIdentifier(unlinked)] = .notImported
                context.delete(unlinked)
                continue
            }
            unlinked.isBalanceAdjustment = true
            unlinked.category = adjustmentReasons[type]
            unmatched[ObjectIdentifier(unlinked)] = .balanceAdjustment
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
                unmatched[ObjectIdentifier(transaction)].map { .init(row: row, outcome: $0) }
            }
        )
    }

    /// Adds the wallet `row` names, at the end of the order, with a $0 Starting balance on the earliest day any row
    /// of it is dated, entered before every row.
    private mutating func addWallet(firstSeenIn row: MoneyLoverRow) throws {
        var draft = WalletDraft()
        draft.name = row.walletName
        let firstDay = rows.filter { $0.walletName == row.walletName }.map(\.day).min() ?? row.day
        wallets[row.walletName] = try Wallet.insert(
            draft, startingBalance: Money(cents: 0), on: firstDay,
            enteredAt: now.addingTimeInterval(-Double(rows.count + walletOrder.count + 1)), in: context
        )
        walletOrder.append(row.walletName)
    }

    /// Works out which rows are paid with a Card, from the card hashtags in their notes, and adds those Cards in the
    /// order ``MoneyLoverCardTag/all`` lists them, so every Card has rows. A row only gets a Card where the app would
    /// offer one (``TransactionDraft/offersCard``, ``Card/pickerChoices(for:keeping:)``): never on a transfer row,
    /// linked or not, and only in the Card's paying wallet. That is Checking (Navy Federal), or when the file has no
    /// such wallet, the wallet of the first row the Card could be given on.
    ///
    /// Returns, for each row filed under `categories`, its Card and its note without that Card's hashtag; or no Card
    /// and its note as it is, hashtag included.
    private mutating func addCards(for categories: [Category]) throws -> [(card: Card?, note: String)] {
        var payingWallets: [MoneyLoverCardTag: Wallet] = [:]
        let tagged = rows.indices.map { index -> (tag: MoneyLoverCardTag, noteWithoutTag: String)? in
            let row = rows[index]
            guard !categories[index].isTransferHalf, let wallet = wallets[row.walletName],
                  let tagged = MoneyLoverCardTag.extractFirst(from: row.note)
            else { return nil }
            let payingWallet = payingWallets[tagged.tag] ?? wallets[MoneyLoverCardTag.payingWalletName] ?? wallet
            payingWallets[tagged.tag] = payingWallet
            return payingWallet == wallet ? tagged : nil
        }
        let used = Set(tagged.compactMap { $0?.tag })
        for tag in MoneyLoverCardTag.all where used.contains(tag) {
            let draft = CardDraft(name: tag.cardName, kind: tag.kind, payingWallet: payingWallets[tag], color: tag.color)
            cards[tag] = try Card.insert(draft, in: context)
        }
        return zip(rows, tagged).map { row, tagged in
            tagged.map { (cards[$0.tag], $0.noteWithoutTag) } ?? (nil, row.note)
        }
    }

    /// Records `row`, the `index`th of the file. The file lists a day's rows newest first, so each row is entered a
    /// second before the one above it and they keep the file's order within a day.
    private func record(
        _ row: MoneyLoverRow, at index: Int, filedUnder category: Category, paidWith card: Card?, note: String
    ) -> Transaction {
        let transaction = Transaction(
            amount: row.amount, day: row.day, wallet: nil, category: nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        transaction.createdAt = now.addingTimeInterval(-Double(index))
        transaction.withName = row.withName
        transaction.eventName = row.eventName
        transaction.isExcludedFromReport = row.isExcludedFromReport
        context.insert(transaction)
        transaction.wallet = wallets[row.walletName]
        transaction.category = category
        transaction.card = card
        return transaction
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

    /// Links each Debt Collection among `imported` to the earliest Loan still open that it pays back in full (same
    /// wallet and amount, dated on or before it: ``Transaction/isPaidBackInFull(by:)``), and each Repayment to a Debt
    /// the same way (ADR-0003). Payments are taken oldest first. Returns the payments left unlinked. Doesn't save.
    private static func linkPayments(among imported: [Transaction]) throws -> [Transaction] {
        let oldestFirst = Array(imported.inListOrder().reversed())
        var open = oldestFirst.filter(\.isLoanOrDebt)
        var unlinked: [Transaction] = []
        for payment in oldestFirst {
            guard let role = payment.category?.lockedRole, role == .debtCollection || role == .repayment else {
                continue
            }
            guard let index = open.firstIndex(where: { $0.isPaidBackInFull(by: payment) }) else {
                unlinked.append(payment)
                continue
            }
            try open.remove(at: index).linkPaymentWithoutSaving(payment)
        }
        return unlinked
    }
}

/// Files each imported row under the category of its name, found ignoring case, adding the category when none has
/// the name: a new top-level category, an Expense for money going out and an Income for money coming in.
private struct CategoryFiler {
    let catalog: CategoryCatalog
    private var byName: [String: [Category]]

    init(context: ModelContext) throws {
        catalog = CategoryCatalog(context: context)
        byName = Dictionary(grouping: try context.fetch(FetchDescriptor<Category>()), by: { Self.key($0.name) })
    }

    private static func key(_ name: String) -> String { name.lowercased() }

    /// The category named `name` for a row of `amount`, added if there is none: when an Expense and an Income
    /// category share the name, the one of the type the amount's sign gives. Doesn't save.
    mutating func findOrAdd(named name: String, for amount: Money) throws -> Category {
        let type: CategoryType = amount.cents < 0 ? .expense : .income
        let named = byName[Self.key(name), default: []]
        if let match = named.first(where: { $0.type == type }) ?? named.first {
            return match
        }
        let category = try catalog.insert(CategoryDraft(name: name, type: type))
        byName[Self.key(name)] = [category]
        return category
    }
}
