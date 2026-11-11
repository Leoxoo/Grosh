import Foundation
import SwiftData

/// What the Adjust Balance sheet holds: the wallet's real balance on a day. Saving records the difference from
/// what the wallet's transactions add up to (its recorded balance) as one balance adjustment.
nonisolated struct BalanceAdjustmentDraft {
    /// Changing it starts the real balance again from this wallet's recorded one, read with
    /// ``readRecordedBalance(from:)``: what was typed belonged to the other wallet.
    var wallet: Wallet? {
        didSet {
            if wallet != oldValue {
                typedEntry = nil
                recordedBalance = nil
            }
        }
    }
    /// The day the real balance is true on, and the date of the adjustment. Changing it keeps a real balance
    /// already typed; until one is, the real balance follows the recorded balance on the new day, read with
    /// ``readRecordedBalance(from:)``.
    var day: CalendarDay {
        didSet {
            if day != oldValue {
                recordedBalance = nil
            }
        }
    }
    var note = ""
    /// Off by default: an adjustment counts in reports like any other transaction.
    var isExcludedFromReport = false
    /// What the wallet's transactions add up to on `day` (``WalletBalances``), or `nil` without a wallet. The sheet
    /// gives it, and reads it again when the wallet or the day changes, so the draft never adds the wallet up itself;
    /// until it is read again there is nothing to adjust, so a difference is never taken from another wallet or day.
    private(set) var recordedBalance: Money?

    /// The reason for money found and for money missing, unless the user picks another.
    private let defaultReasons: [CategoryType: Category]
    /// The reason the user picked, kept while the difference changes sign so it comes back with the sign.
    private var pickedReason: Category?
    /// The real balance as typed on the keypad, or `nil` until the user types one.
    private var typedEntry: AmountEntry?

    /// Starts from the wallet's `recordedBalance` on `day`, so there is nothing to adjust until the real balance is
    /// typed. `defaultReasons` are ``defaultReasons(in:)``.
    init(
        wallet: Wallet?, day: CalendarDay, recordedBalance: Money?, defaultReasons: [CategoryType: Category]
    ) {
        self.wallet = wallet
        self.day = day
        self.recordedBalance = recordedBalance
        self.defaultReasons = defaultReasons
    }

    /// Reads the recorded balance of the wallet on `day` again from `transactions`, every transaction outside
    /// Recently Deleted: after the wallet or the day changes.
    mutating func readRecordedBalance(from transactions: some Sequence<some DatedAmount>) {
        recordedBalance = wallet.map { WalletBalances(transactions, asOf: day).balance(of: $0) }
    }

    var currencyCode: String { wallet.currencyCodeOrDefault }

    /// The real balance on the keypad: what the user typed, or until they type, the recorded balance on `day`,
    /// which the first digit replaces.
    var realBalanceEntry: AmountEntry {
        get { typedEntry ?? AmountEntry(cents: recordedBalance?.cents ?? 0, kind: .balance) }
        set { typedEntry = newValue }
    }

    /// What the wallet really holds on `day`, or `nil` while the keypad can't work it out (dividing by zero).
    /// Setting it types it; setting `nil` starts again from the recorded balance.
    var realBalance: Money? {
        get { realBalanceEntry.cents.map { Money(cents: $0, currencyCode: currencyCode) } }
        set { typedEntry = newValue.map { AmountEntry(cents: $0.cents, kind: .balance) } }
    }

    /// How far the real balance is from the recorded one: what the adjustment adds (above zero) or takes away.
    var difference: Money? {
        guard let recordedBalance, let realBalance else { return nil }
        return Money(cents: realBalance.cents - recordedBalance.cents, currencyCode: recordedBalance.currencyCode)
    }

    /// The type the reason must be: Income when the real balance is higher, Expense when it is lower, `nil` while
    /// there is nothing to adjust.
    var reasonType: CategoryType? {
        difference.flatMap { Self.reasonType(for: $0.cents) }
    }

    /// Income for money found, Expense for money missing, `nil` for no difference.
    static func reasonType(for differenceCents: Int) -> CategoryType? {
        differenceCents > 0 ? .income : differenceCents < 0 ? .expense : nil
    }

    /// The reason a balance adjustment is filed under unless another is picked, by type: Other Income for money
    /// found, Other Expense for money missing.
    static func defaultReasons(in context: ModelContext) throws -> [CategoryType: Category] {
        try [CategoryType.income, .expense].reduce(into: [:]) { reasons, type in
            reasons[type] = try context.otherCategory(type)
        }
    }

    /// The reason the adjustment is filed under: any category of ``reasonType``, the default reason unless the user
    /// picks another. A pick of the other type gives way to the default until the sign comes back.
    var category: Category? {
        get {
            guard let reasonType else { return nil }
            if let pickedReason, pickedReason.type == reasonType { return pickedReason }
            return defaultReasons[reasonType]
        }
        set { pickedReason = newValue }
    }

    /// Checks there is a wallet, a real balance and something to adjust before anything is saved.
    func validate() throws {
        guard wallet != nil else { throw TransactionRuleError.missingWallet }
        guard realBalance != nil else { throw BalanceAdjustmentRuleError.missingRealBalance }
        guard reasonType != nil else { throw BalanceAdjustmentRuleError.nothingToAdjust }
    }
}

/// Why a balance adjustment can't be recorded.
nonisolated enum BalanceAdjustmentRuleError: Error, Equatable {
    /// The keypad can't work out the real balance typed, such as when dividing by zero.
    case missingRealBalance
    /// The real balance is what the wallet's transactions already add up to.
    case nothingToAdjust
    /// The reason must be an Income category for money found and an Expense category for money missing.
    case reasonDoesNotMatchDifference
}

extension BalanceAdjustmentRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingRealBalance:
            String(localized: Strings.BalanceAdjustment.enterRealBalance)
        case .nothingToAdjust:
            String(localized: Strings.BalanceAdjustment.alreadyThisBalance)
        case .reasonDoesNotMatchDifference:
            String(localized: Strings.BalanceAdjustment.reasonCategoryType)
        }
    }
}

extension Transaction {
    /// Records the difference between the draft's real balance and its wallet's recorded balance as one balance
    /// adjustment on the draft's day, so the wallet's balance on that day becomes the real one. Saves.
    @discardableResult
    static func adjustBalance(_ draft: BalanceAdjustmentDraft, in context: ModelContext) throws -> Transaction {
        try draft.validate()
        guard let wallet = draft.wallet, let difference = draft.difference else {
            throw TransactionRuleError.missingWallet
        }
        return try recordBalanceAdjustment(
            difference, in: wallet, on: draft.day, reason: draft.category, note: draft.note,
            isExcludedFromReport: draft.isExcludedFromReport, in: context
        )
    }

    /// Records a known `difference` as a balance adjustment in `wallet` on `day`: money found (above zero) or
    /// missing (below zero). Its `reason` is an Income category for money found and an Expense category for money
    /// missing; without one it is Other Income or Other Expense. It counts in reports unless excluded, and never
    /// needs a Card. Saves.
    @discardableResult
    static func recordBalanceAdjustment(
        _ difference: Money,
        in wallet: Wallet,
        on day: CalendarDay,
        reason: Category? = nil,
        note: String = "",
        isExcludedFromReport: Bool = false,
        in context: ModelContext
    ) throws -> Transaction {
        guard let type = BalanceAdjustmentDraft.reasonType(for: difference.cents) else {
            throw BalanceAdjustmentRuleError.nothingToAdjust
        }
        let category = try reason ?? context.otherCategory(type)
        guard category.type == type else { throw BalanceAdjustmentRuleError.reasonDoesNotMatchDifference }

        let adjustment = Transaction.insert(
            difference, on: day, wallet: wallet, category: category,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines), in: context
        )
        adjustment.isExcludedFromReport = isExcludedFromReport
        adjustment.isBalanceAdjustment = true
        try context.save()
        return adjustment
    }

    /// For a balance adjustment, its wallet's balance just before it (what was recorded) and just after (the
    /// actual balance), taking the wallet's transactions in list order: what is entered later the same day
    /// comes after it. `nil` for any other transaction. Added up from `ledger`, the ledger entries of every
    /// transaction outside Recently Deleted; only the few entered on the adjustment's own day are read for their order.
    func balanceChange(in ledger: some Sequence<LedgerEntry>) -> (recorded: Money, actual: Money)? {
        guard isBalanceAdjustment, let wallet else { return nil }
        let day = dayRaw
        let recordedCents = ledger.reduce(0) { cents, entry in
            guard entry.wallet === wallet, entry.dayRaw <= day, entry.transaction != self else { return cents }
            let isEarlier = entry.dayRaw < day || isListed(before: entry.transaction)
            return isEarlier ? cents + entry.netCents : cents
        }
        return (
            recorded: Money(cents: recordedCents, currencyCode: wallet.currencyCode),
            actual: Money(cents: recordedCents + amountCents, currencyCode: wallet.currencyCode)
        )
    }
}
