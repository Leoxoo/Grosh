import Foundation

/// What the Add Transaction sheet holds before it is saved. The amount is entered positive; the category
/// sets the sign.
struct TransactionDraft {
    /// Expense, Income or Debt/Loan. Switching it drops a category of the old type. Switching onto or off
    /// Debt/Loan also swaps the Exclude from report switch: to the value the user left there before, or else
    /// to the new type's default. Switching between Expense and Income leaves it alone.
    var type: CategoryType {
        didSet {
            guard type != oldValue else { return }
            if category?.type != type {
                category = nil
            }
            guard (type == .debtLoan) != (oldValue == .debtLoan) else { return }
            let leftBehind = isExcludedFromReport
            isExcludedFromReport = excludedFromReportAcrossDebtLoan ?? TransactionDefaults.isExcludedFromReport(type)
            excludedFromReportAcrossDebtLoan = leftBehind
        }
    }

    /// The Exclude from report value on the other side of the Debt/Loan switch, restored on switching back.
    private var excludedFromReportAcrossDebtLoan: Bool?

    /// Changing it drops the Card, which is only offered on its paying wallet's transactions.
    var wallet: Wallet? {
        didSet {
            if wallet != oldValue {
                card = nil
            }
        }
    }
    /// Entered positive; the category decides whether it adds to or takes from the wallet.
    var amount = Money(cents: 0)
    var category: Category?
    var card: Card?
    var note = ""
    var day: CalendarDay
    /// The person the transaction involved.
    var withName = ""
    var isExcludedFromReport = false
    /// The Event an imported transaction belongs to. Shown, never edited.
    private(set) var eventName = ""
    /// Set when editing a balance adjustment, which never needs a Card and is never a Loan or Debt. Saving keeps
    /// the transaction one.
    private(set) var isBalanceAdjustment = false

    init(type: CategoryType, day: CalendarDay) {
        self.type = type
        self.day = day
    }

    /// The transaction as it is, to edit.
    init(editing transaction: Transaction) {
        self.init(copying: transaction, day: transaction.day)
        eventName = transaction.eventName
        isBalanceAdjustment = transaction.isBalanceAdjustment
    }

    /// A new transaction like `transaction`, dated `today` ("Duplicate").
    init(duplicating transaction: Transaction, on today: CalendarDay) {
        self.init(copying: transaction, day: today)
    }

    private init(copying transaction: Transaction, day: CalendarDay) {
        self.init(type: transaction.category?.type ?? .expense, day: day)
        wallet = transaction.wallet
        amount = Money(cents: abs(transaction.amountCents), currencyCode: transaction.amount.currencyCode)
        category = transaction.category
        card = transaction.card
        note = transaction.note
        withName = transaction.withName
        isExcludedFromReport = transaction.isExcludedFromReport
    }
}

/// Why a transaction can't be saved yet.
nonisolated enum TransactionRuleError: Error, Equatable {
    case missingWallet
    /// The amount must be above zero; the category sets the sign.
    case missingAmount
    case missingCategory
    /// An expense in a wallet that has a Card must say which Card paid for it.
    case missingCard
    /// Only a wallet's Starting balance is edited as one.
    case notAStartingBalance
}

extension TransactionRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingWallet: String(localized: "Choose a wallet.")
        case .missingAmount: String(localized: "Enter an amount above zero.")
        case .missingCategory: String(localized: "Choose a category.")
        case .missingCard: String(localized: "Choose the Card this expense was paid with.")
        case .notAStartingBalance: String(localized: "Only a wallet's Starting balance can be edited here.")
        }
    }
}

extension TransactionDraft {
    /// Checks the draft against the transaction rules before anything is saved.
    func validate() throws {
        guard wallet != nil else { throw TransactionRuleError.missingWallet }
        guard amount.cents > 0 else { throw TransactionRuleError.missingAmount }
        guard category != nil else { throw TransactionRuleError.missingCategory }
        guard types.contains(type) || !isBalanceAdjustment else {
            throw BalanceAdjustmentError.reasonDoesNotMatchDifference
        }
        guard card != nil || !requiresCard else { throw TransactionRuleError.missingCard }
    }

    /// The types the sheet offers, in order. A balance adjustment is only ever Expense or Income: its reason is a
    /// category of the type its difference matches, never a Loan or Debt.
    var types: [CategoryType] {
        isBalanceAdjustment ? [.expense, .income] : CategoryType.segments
    }

    /// Whether the transaction can name a Card at all: every transaction but the two halves of a transfer.
    var offersCard: Bool {
        category?.isTransferHalf != true
    }

    /// Whether the transaction must name its Card: an expense in a wallet that has at least one (unarchived) Card,
    /// unless it is a balance adjustment. The Card is optional on Income and Debt/Loan, and never offered on a
    /// transfer.
    var requiresCard: Bool {
        type == .expense && !isBalanceAdjustment && offersCard && !Card.pickerChoices(for: wallet, keeping: nil).isEmpty
    }

    /// Whether the amount adds to the wallet (`1`) or takes from it (`-1`): the category's ``Category/sign``, or
    /// before one is chosen, the type's. `0` while a Debt/Loan has neither Loan nor Debt picked.
    var sign: Int {
        category?.sign ?? (type == .expense ? -1 : type == .income ? 1 : 0)
    }

    /// Whether every required field is filled, so Save can be enabled.
    var canSave: Bool { (try? validate()) != nil }
}
