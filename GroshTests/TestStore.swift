import Foundation
import SwiftData
import Testing
@testable import Grosh

/// An in-memory store seeded with the default category tree and one wallet, Checking, seen on ``today``.
@MainActor
struct TestStore {
    /// The day most suites are seen on. The Month graph suites have a day of their own, ``MonthGraphFixture/today``.
    nonisolated static let today = day(2026, 10, 9)

    let container: ModelContainer
    let checking: Wallet
    var context: ModelContext { container.mainContext }
    var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = container.mainContext.addWallet("Checking")
    }

    /// The seeded category named `name` of `type`.
    func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == name && $0.type == type })
    }

    func categoryExists(_ name: String) throws -> Bool {
        try context.fetch(FetchDescriptor<Grosh.Category>()).contains { $0.name == name }
    }

    /// Records `cents` (signed, as it moves the wallet) filed under the seeded `categoryName` on `day`, in Checking unless
    /// another wallet is given.
    @discardableResult
    func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, on day: CalendarDay,
        in wallet: Wallet? = nil
    ) throws -> Transaction {
        Transaction.insert(
            Money(cents: cents), on: day, wallet: wallet ?? checking, category: try category(categoryName, type),
            in: context
        )
    }

    /// Records an expense of `cents` under `category` on the 1st of October, in Checking.
    @discardableResult
    func spend(_ cents: Int, on category: Grosh.Category) -> Transaction {
        Transaction.insert(Money(cents: -cents), on: day(2026, 10, 1), wallet: checking, category: category, in: context)
    }

    /// A monthly Netflix schedule of $15.99 under a new Subscriptions category, in Checking unless another wallet is
    /// given, starting on `start`, as the Recurring editor fills it.
    func netflixDraft(
        starting start: CalendarDay, preset: RepeatPreset = .monthly, wallet: Wallet? = nil, end: RepeatEnd = .forever
    ) -> RecurringDraft {
        var draft = RecurringDraft(startDay: start)
        draft.name = "Netflix"
        draft.amount = Money(cents: 15_99)
        draft.wallet = wallet ?? checking
        draft.category = context.addCategory("Subscriptions")
        draft.preset = preset
        draft.end = end
        return draft
    }

    /// ``netflixDraft(starting:preset:wallet:end:)`` saved, seen on `today`.
    func netflix(
        starting start: CalendarDay, today: CalendarDay = TestStore.today, preset: RepeatPreset = .monthly,
        wallet: Wallet? = nil, end: RepeatEnd = .forever
    ) throws -> RecurringTransaction {
        try RecurringTransaction.create(
            netflixDraft(starting: start, preset: preset, wallet: wallet, end: end), today: today, in: context
        )
    }

    /// What ``AmountEstimate`` makes of `category`'s history in `currencyCode`, from everything in the store. Saves first.
    func estimate(for category: Grosh.Category, currencyCode: String = "USD") throws -> Int? {
        try context.save()
        return AmountEstimate.cents(
            among: try context.fetch(FetchDescriptor<Transaction>()), for: category, currencyCode: currencyCode
        )
    }

    /// An Expense of $30 under Restaurants in Checking on ``today`` with `people`, saved as the Add sheet saves it.
    @discardableResult
    func eat(with people: [Person]) throws -> Transaction {
        var draft = TransactionDraft(type: .expense, day: Self.today)
        draft.wallet = checking
        draft.amount = Money(cents: 30_00)
        draft.category = try category("Restaurants")
        draft.people = people
        return try Transaction.create(draft, in: context)
    }
}

// MARK: - Making things in a store

/// What the suites make in a store, the way the app makes it. Each works in any in-memory container, seeded or not.
@MainActor
extension ModelContext {
    /// Adds a wallet named `name`, with no transactions.
    @discardableResult
    func addWallet(_ name: String, includeInTotal: Bool = true) -> Wallet {
        let wallet = Wallet(name: name)
        wallet.includeInTotal = includeInTotal
        insert(wallet)
        return wallet
    }

    /// The wallet named `name`.
    func wallet(named name: String) throws -> Wallet {
        try #require(try fetch(FetchDescriptor<Wallet>()).first { $0.name == name })
    }

    /// Adds a category of `type` named `name`, under `parent` when one is given.
    @discardableResult
    func addCategory(
        _ name: String, _ type: CategoryType = .expense, parent: Grosh.Category? = nil
    ) -> Grosh.Category {
        let category = Grosh.Category(name: name, type: type, symbolName: "repeat", color: .purple, parent: parent)
        insert(category)
        return category
    }

    /// Adds a Card named `name`, paid from `wallet`, as the Card editor saves it.
    @discardableResult
    func addCard(
        _ name: String = "Apple Card", kind: CardKind = .credit, paidFrom wallet: Wallet, statementDay: Int? = nil
    ) throws -> Card {
        try Card.create(CardDraft(name: name, kind: kind, payingWallet: wallet, statementDay: statementDay), in: self)
    }

    /// Records `cents` (signed, as it moves the wallet) in `wallet` on `day`, entered `seconds` into a fixed moment when
    /// the order of entry matters.
    @discardableResult
    func record(
        _ cents: Int, on day: CalendarDay, in wallet: Wallet?, under category: Grosh.Category? = nil,
        card: Card? = nil, note: String = "", enteredAt seconds: Double? = nil
    ) -> Transaction {
        let transaction = Transaction.insert(
            Money(cents: cents), on: day, wallet: wallet, category: category, card: card, note: note, in: self
        )
        if let seconds { transaction.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }
        return transaction
    }

    /// Adds `name` to the people, or finds them there, as picking them in With does.
    func person(_ name: String) throws -> Person {
        try Person.add(named: name, in: self)
    }

    /// A Person made and saved directly, without the rules ``Person/add(named:phone:in:)`` applies.
    @discardableResult
    func insertPerson(_ name: String, phone: String? = nil, lastUsed: Date = .now) throws -> Person {
        let person = Person(name: name, phone: phone, lastUsedAt: lastUsed)
        insert(person)
        try save()
        return person
    }

    /// Everyone in the store, by name.
    func everyone() throws -> [Person] {
        try fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
    }

    /// How many transactions the store holds, those in Recently Deleted included.
    func transactionCount() throws -> Int {
        try fetchCount(FetchDescriptor<Transaction>())
    }

    /// The notes of every transaction outside Recently Deleted.
    func notDeletedNotes() throws -> Set<String> {
        Set(try fetch(Transaction.notDeleted).map(\.note))
    }

    /// A Loan (`.loan`, money lent) or Debt (`.debt`, money borrowed) of `cents` with `person` in `wallet`, saved as the
    /// Add sheet's Debt/Loan tab saves it, reminding on `reminderDay` when one is given.
    @discardableResult
    func recordLoanOrDebt(
        _ role: LockedRole, _ cents: Int, with person: Person, on day: CalendarDay, in wallet: Wallet,
        remindOn reminderDay: CalendarDay? = nil
    ) throws -> Transaction {
        var draft = TransactionDraft(type: .debtLoan, day: day)
        draft.wallet = wallet
        draft.amount = Money(cents: cents)
        draft.category = try lockedCategory(role)
        draft.people = [person]
        draft.reminderDay = reminderDay
        return try Transaction.create(draft, in: self)
    }

    /// A payment of `cents` on `loanOrDebt` on `day`, as Debts & Loans records it.
    @discardableResult
    func pay(_ cents: Int, on loanOrDebt: Transaction, on day: CalendarDay) throws -> DebtPayment {
        var draft = try DebtPaymentDraft(settling: loanOrDebt, on: day, in: self)
        draft.amount = Money(cents: cents)
        return try DebtPayment.record(draft, in: self)
    }

    /// Forgives what is outstanding on `loanOrDebt` on `day`, under Other Expense for a Loan or Other Income for a Debt.
    func forgive(_ loanOrDebt: Transaction, on day: CalendarDay) throws {
        try Forgiveness.record(ForgiveDraft(forgiving: loanOrDebt, on: day, in: self), in: self)
    }

    /// `cents` paid back on `expense` on `day`.
    @discardableResult
    func payBack(_ cents: Int, on day: CalendarDay, note: String = "", to expense: Transaction) throws -> Reimbursement {
        try Reimbursement.add(ReimbursementDraft(amount: Money(cents: cents), day: day, note: note), to: expense, in: self)
    }

    /// Replaces everything in the store with what `csv`, a Money Lover export, holds, the owner's cards included.
    @discardableResult
    func importMoneyLover(_ csv: String) throws -> MoneyLoverImportSummary {
        try MoneyLoverImport.replaceAllData(with: MoneyLoverCSV.read(csv), cards: .ownersCards, in: self)
    }
}

// MARK: - Reading balances

/// `wallet`'s balance on `today`, as the app's screens add it up (``WalletBalances``) from its transactions outside
/// Recently Deleted.
@MainActor
func walletBalance(_ wallet: Wallet, asOf today: CalendarDay) -> Money {
    WalletBalances(of: [wallet], asOf: today).balance(of: wallet)
}

/// A balance adjustment's recorded and actual balance, as the transaction detail adds them up from the ledger entries
/// of every transaction outside Recently Deleted (``Transaction/balanceChange(in:)``).
@MainActor
func balanceChange(of transaction: Transaction) throws -> (recorded: Money, actual: Money)? {
    let context = try transaction.storeContext()
    return transaction.balanceChange(in: try context.fetch(Transaction.notDeleted).map(LedgerEntry.init))
}

/// The Total of `wallets` on `today`, per currency, as ``WalletBalances/total(of:)`` adds it up.
@MainActor
func walletTotal(_ wallets: [Wallet], asOf today: CalendarDay) -> [Money] {
    WalletBalances(of: wallets, asOf: today).total(of: wallets)
}

extension WalletBalances {
    /// The balances of `wallets` on `today`, from their own transactions outside Recently Deleted.
    @MainActor
    init(of wallets: [Wallet], asOf today: CalendarDay) {
        self.init(wallets.flatMap { ($0.transactions ?? []).notDeleted }, asOf: today)
    }
}

// MARK: - Time

/// `hour` o'clock on `day`, in UTC, for a test that needs a moment rather than a day.
func moment(_ day: CalendarDay, at hour: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour))
        ?? .distantPast
}

// MARK: - Money Lover exports

/// The header row of a Money Lover export.
let moneyLoverHeader = "Id,Date,Category,Amount,Currency,Wallet,Note,With,Event,Exclude from report,Members"

/// A Money Lover export of `rows`, each a line after the header, as Money Lover writes it (CRLF line ends).
func moneyLoverExport(_ rows: String...) -> String {
    moneyLoverExport(rows)
}

func moneyLoverExport(_ rows: [String]) -> String {
    ([moneyLoverHeader] + rows).joined(separator: "\r\n") + "\r\n"
}

// MARK: - Shorthands for production calls

extension Wallet {
    /// Adds a wallet named `name` with its Starting balance, as ``create(_:startingBalance:on:in:)`` does.
    @MainActor
    @discardableResult
    static func create(
        name: String,
        symbolName: String = WalletDraft().symbolName,
        color: PaletteColor = WalletDraft().color,
        includeInTotal: Bool = true,
        startingBalance: Money,
        on day: CalendarDay,
        in context: ModelContext
    ) throws -> Wallet {
        var draft = WalletDraft()
        draft.name = name
        draft.symbolName = symbolName
        draft.color = color
        draft.includeInTotal = includeInTotal
        return try create(draft, startingBalance: startingBalance, on: day, in: context)
    }
}

extension TransactionListing {
    /// The Transactions tab's list of `selection` on `days` from `all`, with their ledger entries read from them.
    init(
        _ all: [Transaction], showing selection: WalletSelection, on days: DayRange,
        filter: TransactionFilter = TransactionFilter()
    ) {
        self.init(all, ledger: all.map(LedgerEntry.init), showing: selection, on: days, filter: filter)
    }
}

extension BalanceAdjustmentDraft {
    /// Adjust Balance in `wallet` on `day`, its recorded balance read from the wallet's own transactions.
    @MainActor
    init(wallet: Wallet?, day: CalendarDay, in context: ModelContext) throws {
        self.init(
            wallet: wallet, day: day, recordedBalance: wallet.map { walletBalance($0, asOf: day) },
            defaultReasons: try Self.defaultReasons(in: context)
        )
    }

    /// Reads the recorded balance again after the wallet or the day changed, as the sheet does.
    mutating func readRecordedBalance() {
        readRecordedBalance(from: (wallet?.transactions ?? []).notDeleted)
    }
}
