import Foundation
import SwiftData

/// What the Add Transaction sheet holds before it is saved. The amount is entered positive; the category
/// sets the sign.
nonisolated struct TransactionDraft {
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
    /// Changing it to a Loan or a Debt keeps only the first of the people in With, since those are with one Person.
    var category: Category? {
        didSet {
            if requiresWith, people.count > 1 {
                people = [people[0]]
            }
        }
    }
    var card: Card?
    var note = ""
    /// Moving it moves the reminder of every + Owes me that still sits a week after it.
    var day: CalendarDay {
        didSet {
            guard day != oldValue else { return }
            let before = ExpectedReimbursement.defaultReminderDay(expenseOn: oldValue)
            let after = ExpectedReimbursement.defaultReminderDay(expenseOn: day)
            for index in owes.indices where owes[index].reminderDay == before {
                owes[index].reminderDay = after
            }
        }
    }
    /// The people in With, in the order they were chosen (ADR-0009). A Loan or Debt takes exactly one; anything else
    /// takes any number. Taking someone out drops the new + Owes me they had; one already saved stays, and saving is
    /// refused until it is removed or they are back (``validateExpectations()``).
    var people: [Person] = [] {
        didSet {
            owes.removeAll { entry in
                entry.existing == nil && !people.contains(where: { $0 === entry.person })
            }
        }
    }
    /// The + Owes me of an Expense, one for each Person who is yet to pay part of it back (ADR-0010).
    var owes: [OwesMeDraft] = []
    var isExcludedFromReport = false
    /// The day a Loan or Debt reminds the user of it, or `nil` for no reminder. Only kept on the Debt/Loan tab.
    var reminderDay: CalendarDay?
    /// The Event an imported transaction belongs to. Shown, never edited.
    private(set) var eventName = ""
    /// Set when editing a balance adjustment, which never needs a Card and is never a Loan or Debt. Saving keeps
    /// the transaction one.
    private(set) var isBalanceAdjustment = false
    /// Set when editing a part of a Split, which stays an Expense or Income, since the parts add up as one amount.
    private(set) var isSplitPart = false
    /// Set when editing a transaction the Card rule doesn't apply to (``requiresCard``).
    private(set) var cardRuleExemption: CardRuleExemption?
    /// Set when editing a Loan or Debt that has payments or was forgiven: what they hold in place.
    private(set) var paymentLock: PaymentLock?
    /// Set when editing an Expense: the expectations it had, so removing one that has payments can be refused.
    private(set) var originalExpectations: [ExpectedReimbursement] = []
    /// Set when editing an Expense that was paid back into another wallet: the wallet it has to stay in.
    private(set) var walletKeptByPaybacks: Wallet?

    /// What the payments on a Loan or Debt, or its Forgiven mark, hold in place while it is edited: the wallet and
    /// category (so the type) they were recorded against, and an amount no lower than what has been paid. Payments in
    /// Recently Deleted hold the wallet and category too, so they still fit when restored. A forgiven one keeps its
    /// amount too, until it is un-forgiven.
    struct PaymentLock {
        let wallet: Wallet?
        let category: Category?
        /// What has been collected or repaid so far, payments in Recently Deleted included.
        let paid: Money
        /// The amount a forgiven Loan or Debt keeps until it is un-forgiven, or `nil` when it isn't forgiven.
        var forgivenOwed: Money?
    }

    init(type: CategoryType, day: CalendarDay) {
        self.type = type
        self.day = day
    }

    /// The transaction as it is, to edit.
    @MainActor init(editing transaction: Transaction) {
        self.init(copying: transaction, day: transaction.day)
        eventName = transaction.eventName
        isBalanceAdjustment = transaction.isBalanceAdjustment
        isSplitPart = transaction.isSplitPart
        cardRuleExemption = transaction.cardRuleExemption
        reminderDay = transaction.reminderDay
        originalExpectations = transaction.orderedExpectations
        owes = originalExpectations.compactMap(OwesMeDraft.init(editing:))
        walletKeptByPaybacks = transaction.hasPaybacksElsewhere ? transaction.wallet : nil
        let deletedPayments = transaction.paymentsInRecentlyDeleted
        // A transaction that isn't a Loan or Debt gives nil, not an error: ?? nil flattens the two nils into one.
        if let context = transaction.modelContext,
           let loanOrDebt = Log.store.attempt("Reading a Loan or Debt", { try LoanOrDebt(transaction, in: context) }) ?? nil,
           !loanOrDebt.payments.isEmpty || transaction.isForgiven || !deletedPayments.isEmpty {
            let deletedCents = deletedPayments.reduce(0) { $0 + abs($1.amountCents) }
            paymentLock = PaymentLock(
                wallet: transaction.wallet, category: transaction.category,
                paid: Money(cents: loanOrDebt.paid.cents + deletedCents, currencyCode: loanOrDebt.paid.currencyCode),
                forgivenOwed: transaction.isForgiven ? loanOrDebt.owed : nil
            )
        }
    }

    /// A new transaction like `transaction`, dated `today` ("Duplicate"). A Loan's or Debt's reminder belonged to
    /// the original, so the copy starts without one.
    init(duplicating transaction: Transaction, on today: CalendarDay) {
        self.init(copying: transaction, day: today)
    }

    /// A new payment toward a Purchase: its wallet, category, Card and note, and its payment amount, dated `today`.
    /// Saving attaches it to the Purchase.
    init(paymentFor recurring: RecurringTransaction, on today: CalendarDay) {
        self.init(type: recurring.category?.type ?? .expense, day: today)
        wallet = recurring.wallet
        amount = Money(cents: abs(recurring.amountCents), currencyCode: recurring.currencyCode)
        category = recurring.category
        card = recurring.card
        note = recurring.note
    }

    private init(copying transaction: Transaction, day: CalendarDay) {
        self.init(type: transaction.category?.type ?? .expense, day: day)
        wallet = transaction.wallet
        amount = Money(cents: abs(transaction.amountCents), currencyCode: transaction.amount.currencyCode)
        category = transaction.category
        card = transaction.card
        note = transaction.note
        people = transaction.orderedPeople
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
    /// A Loan or Debt must say who it is with.
    case missingWith
    /// A Loan or Debt is with one Person, not several (ADR-0009).
    case tooManyWith
    /// Only a wallet's Starting balance is edited as one.
    case notAStartingBalance
}

extension TransactionRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingWallet: String(localized: Strings.Common.chooseAWallet)
        case .missingAmount: String(localized: Strings.Common.enterAmountAboveZero)
        case .missingCategory: String(localized: Strings.Common.chooseACategory)
        case .missingCard: String(localized: Strings.Transactions.missingCard)
        case .missingWith: String(localized: Strings.Transactions.missingWith)
        case .tooManyWith: String(localized: Strings.Transactions.tooManyWith)
        case .notAStartingBalance: String(localized: Strings.Transactions.notAStartingBalance)
        }
    }
}

nonisolated extension TransactionDraft {
    /// Checks the draft against the transaction rules before anything is saved.
    func validate() throws {
        guard wallet != nil else { throw TransactionRuleError.missingWallet }
        guard amount.cents > 0 else { throw TransactionRuleError.missingAmount }
        guard category != nil else { throw TransactionRuleError.missingCategory }
        guard types.contains(type) || !isBalanceAdjustment else {
            throw BalanceAdjustmentRuleError.reasonDoesNotMatchDifference
        }
        if let paymentLock, let forgivenOwed = paymentLock.forgivenOwed {
            guard wallet == paymentLock.wallet, category == paymentLock.category, amount.cents == forgivenOwed.cents
            else { throw DebtLoanRuleError.lockedByForgiveness }
        } else if let paymentLock {
            guard wallet == paymentLock.wallet, category == paymentLock.category else {
                throw DebtLoanRuleError.lockedByPayments
            }
            guard amount.cents >= paymentLock.paid.cents else { throw DebtLoanRuleError.amountBelowPaid }
        }
        guard card != nil || !requiresCard else { throw TransactionRuleError.missingCard }
        guard !isMissingWith else { throw TransactionRuleError.missingWith }
        guard !(requiresWith && people.count > 1) else { throw TransactionRuleError.tooManyWith }
        try validateExpectations()
    }

    /// Whether this is a Loan or Debt with payments or forgiven, whose wallet, type and category can't change.
    var isLockedByPayments: Bool { paymentLock != nil }

    /// Whether the transaction can carry a reminder date: only a Loan or a Debt, on the Debt/Loan tab.
    var offersReminder: Bool {
        type == .debtLoan
    }

    /// Whether the transaction must say who it is with, and with exactly one Person: a Loan or a Debt.
    var requiresWith: Bool {
        category?.isLoanOrDebt == true
    }

    /// Whether a Loan or Debt still says nobody in With.
    var isMissingWith: Bool {
        requiresWith && people.isEmpty
    }

    /// The types the sheet offers, in order. A balance adjustment is only ever Expense or Income: its reason is a
    /// category of the type its difference matches, never a Loan or Debt. A part of a Split is never a Loan or Debt
    /// either.
    var types: [CategoryType] {
        isBalanceAdjustment || isSplitPart ? [.expense, .income] : CategoryType.segments
    }

    /// Whether the transaction can name a Card at all: every transaction but the two halves of a transfer.
    var offersCard: Bool {
        category?.isTransferHalf != true
    }

    /// The Card rule: whether the transaction must name its Card. An expense in a wallet that has at least one
    /// (unarchived) Card must, unless it is exempt (``CardRuleExemption``). The Card is optional on Income and
    /// Debt/Loan, and never offered on a transfer.
    var requiresCard: Bool {
        type == .expense && cardRuleExemption == nil && offersCard
            && !Card.pickerChoices(for: wallet, keeping: nil).isEmpty
    }
}

/// Why an expense in a wallet with a Card needn't name one: it isn't card spending.
nonisolated enum CardRuleExemption: Hashable, Sendable {
    /// A balance adjustment: the difference between a wallet's recorded and real balance.
    case balanceAdjustment
    /// What a Loan or Debt writes off inside its own flow: what was repaid above a Debt, or the expense of forgiving a
    /// Loan recorded before forgiving became a mark (ADR-0004).
    case debtWriteOff
}

extension Transaction {
    /// Why the Card rule doesn't apply to this transaction, or `nil` when it does.
    var cardRuleExemption: CardRuleExemption? {
        if isBalanceAdjustment { return .balanceAdjustment }
        if isDebtWriteOff { return .debtWriteOff }
        return nil
    }
}

nonisolated extension TransactionDraft {

    /// Whether the amount adds to the wallet (`1`) or takes from it (`-1`): the category's ``Category/sign``, or
    /// before one is chosen, the type's. `0` while a Debt/Loan has neither Loan nor Debt picked.
    var sign: Int {
        category?.sign ?? (type == .expense ? -1 : type == .income ? 1 : 0)
    }

    /// Whether every required field is filled, so Save can be enabled.
    var canSave: Bool { (try? validate()) != nil }
}
