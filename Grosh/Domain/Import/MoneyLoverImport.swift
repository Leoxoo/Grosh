import Foundation
import SwiftData

/// Import from MoneyLover ("Replace all data"): a MoneyLover CSV export replaces every wallet, Card, Person and
/// transaction. The categories are kept.
enum MoneyLoverImport {
    /// Whether an import is under way: its changes are in the main context, unsaved, until its last step. Work that
    /// saves the main context on its own, such as the startup work when the app comes back to the foreground, waits
    /// till it is over, so as not to save half an import.
    private(set) static var isRunning = false

    /// Replaces the wallets, Cards, people and transactions in `context` with the rows of `export`, a MoneyLover export
    /// as ``MoneyLoverCSV/read(_:currencyCode:)`` reads it, entered at `now`, its notes naming Cards by the hashtags of
    /// `cards`:
    ///
    /// - Each wallet is created once by name, in the currency of its first row, with a Starting balance of nothing on
    ///   its first day.
    /// - Each row is filed under the category of its name; a name no category has becomes a new top-level category.
    /// - A card hashtag in a note becomes the row's Card (``MoneyLoverCardTag``), where the app would offer that Card:
    ///   not on a transfer row, and only in the Card's paying wallet. Elsewhere the hashtag stays in the note.
    /// - Outgoing and Incoming transfer rows link into transfers. One with no partner becomes a balance adjustment,
    ///   filed as Adjust Balance files it; one of no amount has nothing to adjust and isn't imported.
    /// - Each Debt Collection links to the earliest open Loan of its wallet and amount, each Repayment to a Debt.
    /// - A row's With becomes one Person, created the first time its name is read and reused after, ignoring case
    ///   (ADR-0009), and last used when its newest transaction was entered.
    /// - Within a day, rows keep the file's order.
    ///
    /// A Grosh export (``GroshCSVExport``) is restored as it was instead: each row gets the Card its `Card` column
    /// names, its note stays as it is, rows sharing a `Linked` value are linked, and a wallet's Starting balance is the
    /// file's own row rather than a $0 one. A With of several names, as the export joins them with `; `, becomes
    /// several people. Nothing is left unmatched.
    ///
    /// Saves once, at the end: the old data is deleted by the same save that adds the new and rebuilds every saved month
    /// total (ADR-0013). Throws without changing anything when it can't finish, saving included, and
    /// ``MoneyLoverImportError/noTransactions`` for no rows. Once saved, the old data can't be brought back.
    ///
    /// Runs every step of a ``Run`` at once; Import from MoneyLover's screen runs them one at a time instead, to show
    /// how far it has got.
    @discardableResult
    static func replaceAllData(
        with export: MoneyLoverExport, cards: MoneyLoverCardMapping, in context: ModelContext, now: Date = .now
    ) throws -> MoneyLoverImportSummary {
        let run = try Run(export: export, cards: cards, in: context, now: now)
        while true {
            if let summary = try run.next() { return summary }
        }
    }

    /// One import, ``replaceAllData(with:cards:in:now:)``, done a step at a time, so a screen can show how far it has
    /// got between steps. Until the last step saves, the import's changes are in the context unsaved: the context
    /// doesn't autosave meanwhile, and ``isRunning`` says to hold off other saves.
    final class Run {
        private enum Step { case remove, prepare, record, finish, save, done }

        /// How many old transactions or rows one step deletes or records: about a tenth of a second's work on an
        /// iPhone, so the progress moves smoothly without making the import longer.
        private static let sliceSize = 1_000

        private let context: ModelContext
        private var importer: Importer
        private let wasAutosaving: Bool
        private var step = Step.remove
        /// The old transactions, read by the first step and deleted a slice at a time.
        private var oldTransactions: [Transaction]?
        private let oldCount: Int
        private var removed = 0
        private var recorded = 0
        private var summary: MoneyLoverImportSummary?

        /// Starts an import of `export` into `context`; nothing changes until ``next()`` runs its first step. Throws
        /// ``MoneyLoverImportError/noTransactions`` for an export of no rows.
        init(export: MoneyLoverExport, cards: MoneyLoverCardMapping, in context: ModelContext, now: Date = .now) throws {
            guard !export.rows.isEmpty else { throw MoneyLoverImportError.noTransactions }
            importer = try Importer(export: export, cardMapping: cards, context: context, now: now)
            self.context = context
            oldCount = try context.fetchCount(FetchDescriptor<Transaction>())
            wasAutosaving = context.autosaveEnabled
            context.autosaveEnabled = false
            MoneyLoverImport.isRunning = true
        }

        /// Whether the next step is the save. It is the longest, and a screen can't draw anything new while it runs.
        var isSaving: Bool { step == .save }

        /// How far the import has got, from 0 to 1. The steps before the save fill the first 90%, each by the time it
        /// takes as measured on the 16k store (deleting an old transaction takes about as long as recording a row). The
        /// save is the rest: it can't report how far it has got, and a bar that waits at 90% looks nearly done, where
        /// one that waits halfway, as the save's real share of the time would put it, looks stuck.
        var fractionDone: Double {
            let beforeSave = 0.9
            let old = Double(oldCount)
            let rows = Double(importer.rows.count)
            let steps: [(Step, Double)] = [
                (.remove, old * 0.7),
                (.prepare, rows * 0.6),
                (.record, rows),
                (.finish, old * 0.15 + rows * 0.15),
            ]
            switch step {
            case .save: return beforeSave
            case .done: return 1
            default: break
            }
            var done = 0.0
            for (each, time) in steps {
                if each == step {
                    switch step {
                    case .remove: done += time * Double(removed) / max(old, 1)
                    case .record: done += time * Double(recorded) / max(rows, 1)
                    default: break
                    }
                    break
                }
                done += time
            }
            return beforeSave * done / steps.reduce(0) { $0 + $1.1 }
        }

        /// Runs the next step, and once the last one has saved, returns what was imported. When a step throws, the
        /// context is rolled back, so nothing has changed, and the run is over.
        func next() throws -> MoneyLoverImportSummary? {
            do {
                return try Signpost.interval("Import CSV step") { try runStep() }
            } catch {
                context.rollback()
                end()
                throw error
            }
        }

        private func runStep() throws -> MoneyLoverImportSummary? {
            switch step {
            case .remove:
                let old = try oldTransactions ?? MoneyLoverImport.removeAllButTransactions(in: context)
                let slice = old[removed..<min(removed + Self.sliceSize, old.count)]
                for transaction in slice { context.delete(transaction) }
                removed += slice.count
                oldTransactions = old
                if removed == old.count {
                    oldTransactions = nil
                    step = .prepare
                }
            case .prepare:
                try importer.prepare()
                step = .record
            case .record:
                let end = min(recorded + Self.sliceSize, importer.rows.count)
                try importer.record(recorded..<end)
                recorded = end
                if recorded == importer.rows.count { step = .finish }
            case .finish:
                summary = try importer.finish()
                // Everything is replaced, so every saved month total is counted again, in the same save (ADR-0013).
                try WalletMonthTotals.rebuild(in: context)
                step = .save
            case .save:
                try context.save()
                end()
                return summary
            case .done:
                return summary
            }
            return nil
        }

        private func end() {
            step = .done
            context.autosaveEnabled = wasAutosaving
            MoneyLoverImport.isRunning = false
        }
    }

    /// Deletes every Card, Person and wallet, and returns every transaction for the caller to delete. Categories stay.
    /// Doesn't save.
    ///
    /// One by one, rather than as batch deletes, which take effect in the store right away, where a rollback can't
    /// undo them. Each category, Card, Person and wallet lets go of its transactions first: left to update those lists
    /// one deleted transaction at a time, saving ~6,000 deletes takes several seconds rather than a fraction of one.
    fileprivate static func removeAllButTransactions(in context: ModelContext) throws -> [Transaction] {
        for category in try context.fetch(FetchDescriptor<Category>()) {
            category.transactions = []
            category.forgivenTransactions = []
        }
        for card in try context.fetch(FetchDescriptor<Card>()) {
            card.transactions = []
            context.delete(card)
        }
        for person in try context.fetch(FetchDescriptor<Person>()) {
            person.transactions = []
            context.delete(person)
        }
        for wallet in try context.fetch(FetchDescriptor<Wallet>()) {
            wallet.transactions = []
            wallet.cards = []
            context.delete(wallet)
        }
        return try context.fetch(FetchDescriptor<Transaction>())
    }
}

/// The new data of one ``MoneyLoverImport/Run``, added after the old data is deleted: ``prepare()``, then
/// ``record(_:)`` for every row, then ``finish()``.
private struct Importer {
    let rows: [MoneyLoverRow]
    /// Whether the file is a Grosh export, restored as it was exported.
    let isGroshExport: Bool
    let cardMapping: MoneyLoverCardMapping
    let context: ModelContext
    let now: Date
    /// What a transfer row with no partner is filed under as a balance adjustment, by the adjustment's reason type.
    let adjustmentReasons: [CategoryType: Category]

    private var wallets: [String: Wallet] = [:]
    private var walletOrder: [String] = []
    private var cards: [MoneyLoverCardTag: Card] = [:]
    private var people = PeopleByName()
    private var categories: CategoryFiler
    /// For each row, the category it is filed under.
    private var filed: [Category] = []
    /// For each row, the people it is with.
    private var withPeople: [[Person]] = []
    /// For each row, its Card and note: from its card hashtag, or for a Grosh export, its `Card` column.
    private var paid: [(card: Card?, note: String)] = []
    private var namedCardsCreated = 0
    /// The rows recorded so far, `imported[i]` being `rows[i]`.
    private var imported: [Transaction] = []
    /// A Grosh export's rows by their `Linked` value.
    private var linked: [String: [Transaction]] = [:]

    init(export: MoneyLoverExport, cardMapping: MoneyLoverCardMapping, context: ModelContext, now: Date) throws {
        self.rows = export.rows
        self.isGroshExport = export.isGroshExport
        self.cardMapping = cardMapping
        self.context = context
        self.now = now
        adjustmentReasons = try BalanceAdjustmentDraft.defaultReasons(in: context)
        categories = try CategoryFiler(context: context)
    }

    /// Files every row under its category, and adds the wallets, people and Cards the rows name. Doesn't save.
    mutating func prepare() throws {
        // A row's sign says which type of category it is filed under when an Expense and an Income share its name.
        filed = try rows.map { row in
            try categories.findOrAdd(named: row.categoryName, as: row.amount.cents < 0 ? .expense : .income)
        }
        for row in rows where wallets[row.walletName] == nil {
            let hasStartingBalance = isGroshExport && rows.indices.contains { index in
                rows[index].walletName == row.walletName && filed[index].lockedRole == .startingBalance
            }
            try addWallet(firstSeenIn: row, withStartingBalance: !hasStartingBalance)
        }
        withPeople = addPeople(splittingNames: isGroshExport)
        if isGroshExport {
            let named = try addNamedCards()
            paid = zip(rows, named.cards).map { row, card in (card, row.note) }
            namedCardsCreated = named.created
        } else {
            paid = try addCards(for: filed)
        }
    }

    /// Records the rows at `indices`, the next ones after those recorded so far. A Grosh export's rows are recorded as
    /// they were exported: each with the Card its `Card` column names and its note as it is, and a Loan or Debt with
    /// the Forgiven mark its `Forgiven` columns hold. Doesn't save.
    mutating func record(_ indices: Range<Int>) throws {
        for index in indices {
            let row = rows[index]
            let transaction = record(
                row, at: index, filedUnder: filed[index], paidWith: paid[index].card, note: paid[index].note,
                with: withPeople[index]
            )
            imported.append(transaction)
            guard isGroshExport else { continue }
            if let forgiven = row.forgiven, let kind = transaction.loanOrDebtKind {
                try markForgiven(transaction, as: forgiven, kind: kind)
            }
            if let link = row.link, !link.isEmpty {
                linked[link, default: []].append(transaction)
            }
        }
    }

    /// Once every row is recorded, links the transfers and the payments, or a Grosh export's rows that share a
    /// `Linked` value, and says what was done. Doesn't save.
    mutating func finish() throws -> MoneyLoverImportSummary {
        if isGroshExport { return restoreLinks() }
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

    /// Adds the wallet `row` names, in the currency of `row`, the first of it, at the end of the order, and when
    /// `withStartingBalance`, a Starting balance of nothing on the earliest day any row of it is dated, entered before
    /// every row.
    private mutating func addWallet(firstSeenIn row: MoneyLoverRow, withStartingBalance: Bool) throws {
        var draft = WalletDraft(currencyCode: row.amount.currencyCode)
        draft.name = row.walletName
        guard withStartingBalance else {
            wallets[row.walletName] = try Wallet.insertWithoutStartingBalance(draft, in: context)
            walletOrder.append(row.walletName)
            return
        }
        let firstDay = rows.filter { $0.walletName == row.walletName }.map(\.day).min() ?? row.day
        wallets[row.walletName] = try Wallet.insert(
            draft, startingBalance: Money(cents: 0, currencyCode: draft.currencyCode), on: firstDay,
            enteredAt: now.addingTimeInterval(-Double(rows.count + walletOrder.count + 1)), in: context
        )
        walletOrder.append(row.walletName)
    }

    /// Adds the people the rows' With names, each once however many rows name it, and returns for each row the people it
    /// is with. A name is read as it is, or with `splittingNames` as several joined with `; ` (a Grosh export's way).
    /// Doesn't save.
    private mutating func addPeople(splittingNames: Bool) -> [[Person]] {
        var withPeople: [[Person]] = []
        for row in rows {
            let names = splittingNames
                ? row.withName.components(separatedBy: Transaction.withSeparator) : [row.withName]
            withPeople.append(names.compactMap { people.reuseOrCreate($0, lastUsedAt: .distantPast, in: context) })
        }
        return withPeople
    }

    /// Links a Grosh export's rows that share a `Linked` value, and says what was done; the wallets' Starting
    /// balances, which are rows of the file, aren't counted. Nothing is left unmatched. Doesn't save.
    private func restoreLinks() -> MoneyLoverImportSummary {
        // The file numbers each link but doesn't say what it joins: that is worked out from its rows (ADR-0012).
        for members in linked.values {
            Transaction.link(members, as: LinkKind(of: members))
        }
        return MoneyLoverImportSummary(
            wallets: walletOrder.map { name in
                .init(name: name, transactionCount: rows.indices.count { index in
                    rows[index].walletName == name && filed[index].lockedRole != .startingBalance
                })
            },
            cardsCreated: namedCardsCreated,
            unmatchedRows: []
        )
    }

    /// Marks `transaction`, a Loan or Debt, forgiven as a Grosh export's `Forgiven` columns say, under the category
    /// they name for the forgiven amount (an Expense for a Loan, an Income for a Debt), or Other Expense or Other
    /// Income when they name none or only a category of another type. Doesn't save.
    private mutating func markForgiven(
        _ transaction: Transaction, as forgiven: MoneyLoverRow.Forgiven, kind: LoanOrDebtKind
    ) throws {
        let named = try forgiven.categoryName.isEmpty
            ? nil : categories.findOrAdd(named: forgiven.categoryName, as: kind.forgivenType)
        let category = try named.flatMap { $0.type == kind.forgivenType ? $0 : nil }
            ?? context.otherCategory(kind.forgivenType)
        transaction.forgivenCents = forgiven.amount.cents
        transaction.markForgiven(on: forgiven.day, note: forgiven.note)
        transaction.forgivenCategory = category
    }

    /// The Card each row of a Grosh export names in its `Card` column, `nil` for none, and how many Cards were added.
    /// Each Card is added the first time the file names it in a wallet, paid from that wallet. A Card that
    /// ``cardMapping`` names gets its kind and color; any other is a blue Credit card.
    private func addNamedCards() throws -> (cards: [Card?], created: Int) {
        struct Key: Hashable {
            let name: String
            let walletName: String
        }
        var added: [Key: Card] = [:]
        var cards: [Card?] = []
        for row in rows {
            guard let name = row.cardName, !name.isEmpty else {
                cards.append(nil)
                continue
            }
            let key = Key(name: name, walletName: row.walletName)
            if let card = added[key] {
                cards.append(card)
                continue
            }
            let tag = cardMapping.tags.first { $0.cardName.lowercased() == name.lowercased() }
            let card = try Card.insert(
                CardDraft(
                    name: name, kind: tag?.kind ?? .credit, payingWallet: wallets[row.walletName],
                    color: tag?.color ?? .blue
                ),
                in: context
            )
            added[key] = card
            cards.append(card)
        }
        return (cards, added.count)
    }

    /// Works out which rows are paid with a Card, from the card hashtags in their notes, and adds those Cards in the
    /// order ``cardMapping`` lists them, so every Card has rows. A row only gets a Card where the app
    /// would offer one (``TransactionDraft/offersCard``, ``Card/pickerChoices(for:keeping:)``): never on a transfer
    /// row, linked or not, and only in the Card's paying wallet. That is ``MoneyLoverCardMapping/payingWalletName``,
    /// or when the file has no such wallet, the wallet of the first row the Card could be given on.
    ///
    /// Returns, for each row filed under `categories`, its Card and its note without that Card's hashtag; or no Card
    /// and its note as it is, hashtag included.
    private mutating func addCards(for categories: [Category]) throws -> [(card: Card?, note: String)] {
        var payingWallets: [MoneyLoverCardTag: Wallet] = [:]
        let tagged = rows.indices.map { index -> (tag: MoneyLoverCardTag, noteWithoutTag: String)? in
            let row = rows[index]
            guard !categories[index].isTransferHalf, let wallet = wallets[row.walletName],
                  let tagged = MoneyLoverCardTag.extractFirst(from: row.note, among: cardMapping.tags)
            else { return nil }
            let payingWallet = payingWallets[tagged.tag]
                ?? cardMapping.payingWalletName.flatMap { wallets[$0] }
                ?? wallet
            payingWallets[tagged.tag] = payingWallet
            return payingWallet == wallet ? tagged : nil
        }
        let used = Set(tagged.compactMap { $0?.tag })
        for tag in cardMapping.tags where used.contains(tag) {
            cards[tag] = try Card.insert(
                CardDraft(name: tag.cardName, kind: tag.kind, payingWallet: payingWallets[tag], color: tag.color),
                in: context
            )
        }
        return zip(rows, tagged).map { row, tagged in
            tagged.map { (cards[$0.tag], $0.noteWithoutTag) } ?? (nil, row.note)
        }
    }

    /// Records `row`, the `index`th of the file. The file lists a day's rows newest first, so each row is entered a
    /// second before the one above it and they keep the file's order within a day.
    private func record(
        _ row: MoneyLoverRow, at index: Int, filedUnder category: Category, paidWith card: Card?, note: String,
        with chosen: [Person]
    ) -> Transaction {
        let transaction = Transaction.insert(
            cents: row.amount.cents, on: row.day, wallet: wallets[row.walletName], category: category, card: card,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines), in: context
        )
        transaction.createdAt = now.addingTimeInterval(-Double(index))
        transaction.eventName = row.eventName
        transaction.isExcludedFromReport = row.isExcludedFromReport
        transaction.setPeople(chosen, usedAt: transaction.createdAt)
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
            Transaction.link([outgoing, partner], as: .transfer)
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
            guard payment.paidLoanOrDebtKind != nil else { continue }
            guard let index = open.firstIndex(where: { $0.isPaidBackInFull(by: payment) }) else {
                unlinked.append(payment)
                continue
            }
            try open.remove(at: index).linkPayment(payment)
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

    /// The category named `name`, added as a `type` category if there is none: when categories of several types share
    /// the name, the one of `type`. Doesn't save.
    mutating func findOrAdd(named name: String, as type: CategoryType) throws -> Category {
        let named = byName[Self.key(name), default: []]
        if let match = named.first(where: { $0.type == type }) ?? named.first {
            return match
        }
        let category = try catalog.insert(CategoryDraft(name: name, type: type))
        byName[Self.key(name)] = [category]
        return category
    }
}
