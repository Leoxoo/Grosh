import Foundation
import SwiftData

/// What the Adjust Balance sheet holds: the wallet's real balance on a day. Saving records the difference from
/// what the wallet's transactions add up to as one balance adjustment.
struct BalanceAdjustmentDraft {
    /// Changing it starts the real balance again from this wallet's recorded one: what was typed belonged to the
    /// other wallet.
    var wallet: Wallet? {
        didSet {
            if wallet != oldValue {
                typedEntry = nil
            }
        }
    }
    /// The day the real balance is true on, and the date of the adjustment. Changing it keeps a real balance
    /// already typed; until one is, the real balance follows the recorded balance on the new day.
    var day: CalendarDay
    var note = ""
    /// Off by default: an adjustment counts in reports like any other transaction.
    var isExcludedFromReport = false

    /// The reason for money found and for money missing, unless the user picks another.
    private let defaultReasons: [CategoryType: Category]
    /// The reason the user picked, kept while the difference changes sign so it comes back with the sign.
    private var pickedReason: Category?
    /// The real balance as typed on the keypad, or `nil` until the user types one.
    private var typedEntry: AmountEntry?

    /// Starts from the wallet's recorded balance on `day`, so there is nothing to adjust until the real balance
    /// is typed.
    init(wallet: Wallet?, day: CalendarDay, in context: ModelContext) throws {
        self.wallet = wallet
        self.day = day
        defaultReasons = try [CategoryType.income, .expense].reduce(into: [:]) { reasons, type in
            reasons[type] = try Self.defaultReason(for: type, in: context)
        }
    }

    var currencyCode: String { wallet?.currencyCode ?? Money.defaultCurrencyCode }

    /// The real balance on the keypad: what the user typed, or until they type, the recorded balance on `day`,
    /// which the first digit replaces.
    var realBalanceEntry: AmountEntry {
        get { typedEntry ?? AmountEntry(cents: recordedBalance?.cents ?? 0) }
        set { typedEntry = newValue }
    }

    /// What the wallet really holds on `day`, or `nil` while the keypad can't work it out (dividing by zero).
    /// Setting it types it; setting `nil` starts again from the recorded balance.
    var realBalance: Money? {
        get { realBalanceEntry.cents.map { Money(cents: $0, currencyCode: currencyCode) } }
        set { typedEntry = newValue.map { AmountEntry(cents: $0.cents) } }
    }

    /// What the wallet's transactions add up to on `day`.
    var recordedBalance: Money? { wallet?.balance(asOf: day) }

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

    /// The reason a balance adjustment of `type` is filed under unless another is picked: Other Income for money
    /// found, Other Expense for money missing.
    static func defaultReason(for type: CategoryType, in context: ModelContext) throws -> Category {
        try context.lockedCategory(type == .income ? .otherIncome : .otherExpense)
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

    /// Whether Save can be enabled.
    var canSave: Bool { (try? validate()) != nil }
}

extension TransactionDefaults {
    /// The starting values of Adjust Balance, dated `today`: in the ``wallet(viewing:in:)`` (the wallet the
    /// screen shows, or else the last-used one), with its real balance at the recorded one.
    static func suggestBalanceAdjustment(
        on today: CalendarDay, viewing viewed: Wallet? = nil, in context: ModelContext
    ) throws -> BalanceAdjustmentDraft {
        try BalanceAdjustmentDraft(wallet: wallet(viewing: viewed, in: context), day: today, in: context)
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
            String(localized: "Enter what the wallet really holds.")
        case .nothingToAdjust:
            String(localized: "The wallet already has this balance.")
        case .reasonDoesNotMatchDifference:
            String(localized: "Choose an Income category when the balance goes up, or an Expense category when it goes down.")
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
        let category = try reason ?? BalanceAdjustmentDraft.defaultReason(for: type, in: context)
        guard category.type == type else { throw BalanceAdjustmentRuleError.reasonDoesNotMatchDifference }

        let adjustment = Transaction(amount: difference, day: day, wallet: nil, category: nil)
        context.insert(adjustment)
        adjustment.wallet = wallet
        adjustment.category = category
        adjustment.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        adjustment.isExcludedFromReport = isExcludedFromReport
        adjustment.isBalanceAdjustment = true
        try context.save()
        return adjustment
    }

    /// For a balance adjustment, its wallet's balance just before it (what was recorded) and just after (the
    /// actual balance), taking the wallet's transactions in list order: what is entered later the same day
    /// comes after it. `nil` for any other transaction.
    var balanceChange: (recorded: Money, actual: Money)? {
        guard isBalanceAdjustment, let wallet else { return nil }
        let recordedCents = (wallet.transactions ?? [])
            .filter { $0 != self && isListed(before: $0) }
            .reduce(0) { $0 + $1.amountCents }
        return (
            recorded: Money(cents: recordedCents, currencyCode: wallet.currencyCode),
            actual: Money(cents: recordedCents + amountCents, currencyCode: wallet.currencyCode)
        )
    }
}
