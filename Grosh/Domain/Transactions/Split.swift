import Foundation
import SwiftData

/// One part of a Split being set up: what a part takes of its own. Every part shares the wallet and Card of the
/// transaction split, so a part holds neither.
nonisolated struct SplitPart {
    /// Entered positive; the category decides whether it adds to or takes from the wallet.
    var amount: Money
    var category: Category?
    var day: CalendarDay
    var note: String
    /// The people in With. A part is never a Loan or Debt, so it takes any number.
    var people: [Person]
    var eventName: String

    /// The part as `transaction` is now.
    init(of transaction: Transaction) {
        amount = Money(cents: abs(transaction.amountCents), currencyCode: transaction.amount.currencyCode)
        category = transaction.category
        day = transaction.day
        note = transaction.note
        people = transaction.orderedPeople
        eventName = transaction.eventName
    }

    /// Sets what this part holds on `transaction`: its amount (signed by its category), category, day, note, With and
    /// Event.
    fileprivate func apply(to transaction: Transaction) {
        transaction.amountCents = amount.cents * (category?.sign ?? 1)
        transaction.category = category
        transaction.day = day
        transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.setPeople(people)
        transaction.eventName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A part of a split being set up: the transaction being split, or a new part by its place in ``SplitDraft/parts``.
nonisolated enum SplitPartRef: Hashable {
    case original
    case part(Int)
}

/// A Reimbursement of the transaction being split and the part it goes to, `nil` until the user chooses.
nonisolated struct SplitReimbursement {
    let reimbursement: Reimbursement
    var part: SplitPartRef?
}

/// What the Split sheet holds before it is applied: the transaction being split as a part of its own, and the parts
/// added to it. The transaction's amount is always what the other parts leave of the total; typing over it changes
/// the total.
nonisolated struct SplitDraft {
    /// What the transaction came to before it was split.
    let was: Money
    /// The transaction being split. Its `amount` is the remainder, which the draft keeps as parts are added, changed
    /// and removed.
    var original: SplitPart
    /// The new parts, in the order they were added.
    private(set) var parts: [SplitPart] = []
    /// The transaction's Reimbursements, each with the part it goes to. Empty when it has none.
    var reimbursements: [SplitReimbursement]

    /// The transaction as it is, with no parts yet and its Reimbursements not yet assigned.
    init(splitting transaction: Transaction) {
        original = SplitPart(of: transaction)
        was = original.amount
        reimbursements = transaction.orderedReimbursements.map { SplitReimbursement(reimbursement: $0) }
    }

    /// What the parts add up to: the original's remainder and every other part. It moves the wallet's balance when it
    /// differs from ``was``.
    var total: Money {
        Money(cents: parts.reduce(original.amount.cents) { $0 + $1.amount.cents }, currencyCode: was.currencyCode)
    }

    /// How much the wallet's balance moves when the split is applied: zero while the parts sum to the original.
    var walletChange: Money {
        Money(cents: (original.category?.sign ?? 0) * (total.cents - was.cents), currencyCode: was.currencyCode)
    }

    /// A part to start from: a copy of the original, with no amount yet.
    func newPart() -> SplitPart {
        var part = original
        part.amount = Money(cents: 0, currencyCode: was.currencyCode)
        return part
    }

    /// Adds `part`, taking its amount off the original.
    mutating func addPart(_ part: SplitPart) {
        parts.append(part)
        original.amount.cents -= part.amount.cents
    }

    /// Replaces the part at `index` with `part`; the original makes up the difference in amount.
    mutating func replacePart(at index: Int, with part: SplitPart) {
        original.amount.cents += parts[index].amount.cents - part.amount.cents
        parts[index] = part
    }

    /// Removes the part at `index`, giving its amount back to the original. Its Reimbursements become unassigned, so the
    /// user chooses again.
    mutating func removePart(at index: Int) {
        original.amount.cents += parts.remove(at: index).amount.cents
        for position in reimbursements.indices {
            guard case .part(let assigned)? = reimbursements[position].part, assigned >= index else { continue }
            reimbursements[position].part = assigned == index ? nil : SplitPartRef.part(assigned - 1)
        }
    }

    /// Checks the draft against the split rules before anything is changed: at least one new part, every part (the
    /// original too) with an amount above zero and a category, and every Reimbursement assigned to a part.
    func validate() throws {
        let everyPart = [original] + parts
        guard !parts.isEmpty else { throw SplitRuleError.noParts }
        guard everyPart.allSatisfy({ $0.amount.cents > 0 }) else { throw SplitRuleError.missingAmount }
        guard everyPart.allSatisfy({ $0.category != nil }) else { throw SplitRuleError.missingCategory }
        guard reimbursements.allSatisfy({ $0.part != nil }) else { throw SplitRuleError.unassignedReimbursement }
    }

    /// Whether every required field is filled, so Split can be enabled.
    var canSplit: Bool { (try? validate()) != nil }
}

/// Why a split can't be made or undone.
nonisolated enum SplitRuleError: Error, Equatable {
    /// Only an ordinary Expense or Income can be split (``Transaction/canBeSplit``).
    case notSplittable
    case noParts
    /// Every part, and what is left on the original, must be above zero.
    case missingAmount
    case missingCategory
    /// Every Reimbursement must go to one of the parts.
    case unassignedReimbursement
    /// The transaction has no other part to merge back.
    case notSplit
}

extension SplitRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notSplittable: String(localized: Strings.Transactions.notSplittable)
        case .noParts: String(localized: Strings.Transactions.noParts)
        case .missingAmount: String(localized: Strings.Transactions.splitMissingAmount)
        case .missingCategory: String(localized: Strings.Transactions.splitMissingCategory)
        case .unassignedReimbursement: String(localized: Strings.Transactions.unassignedReimbursement)
        case .notSplit: String(localized: Strings.Transactions.notSplit)
        }
    }
}

extension Transaction {
    /// Whether the transaction can be split: an ordinary Expense or Income, which is not a transfer half, a Loan or
    /// Debt or one of their payments (or what they write off), a Starting balance, a Balance adjustment, an Expense
    /// paid back into another wallet (ADR-0010), or in Recently Deleted. A part of a split can be split again.
    var canBeSplit: Bool { canBeSplit(editFlow: editFlow) }

    /// ``canBeSplit``, for a screen that has already worked out ``editFlow``.
    func canBeSplit(editFlow: TransactionEditFlow?) -> Bool {
        editFlow == .addSheet && category?.type.isUserManaged == true && !isBalanceAdjustment && !isInRecentlyDeleted
            && !hasPaybacksElsewhere
    }

    /// Whether this is an Expense or Income, not a transfer half, that shares a link: a part of a Split, or what a Loan
    /// or Debt writes off beside a payment. A payback into another wallet and the Expense it was paid against share a
    /// link too, but they are neither (ADR-0010).
    var isLinkedExpenseOrIncome: Bool {
        guard linkID != nil, !hasPaybacksElsewhere, let category, !category.isTransferHalf,
              category.lockedRole != .reimbursement
        else { return false }
        return category.type.isUserManaged
    }

    /// The links Loans and Debts hold, those in Recently Deleted included: what tells a part of a Split from what a Loan
    /// or Debt writes off. There are only ever a few, so one fetch answers ``isSplitPart(loanOrDebtLinks:)`` and
    /// ``isDebtWriteOff(loanOrDebtLinks:)`` for every transaction a screen or an export goes through.
    static func loanOrDebtLinks(in context: ModelContext) throws -> Set<UUID> {
        let loan: String? = LockedRole.loan.rawValue
        let debt: String? = LockedRole.debt.rawValue
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate {
            $0.linkID != nil && ($0.category?.lockedRoleRaw == loan || $0.category?.lockedRoleRaw == debt)
        })
        descriptor.propertiesToFetch = [\.linkID]
        return Set(try context.fetch(descriptor).compactMap(\.linkID))
    }

    /// Whether a Loan or Debt (even one in Recently Deleted) shares this transaction's link. Counts them in the store,
    /// once for each read: a screen or an export asking for many transactions reads ``loanOrDebtLinks(in:)`` instead.
    var sharesLinkWithLoanOrDebt: Bool {
        guard let link = linkID, let context = modelContext else { return false }
        let loan: String? = LockedRole.loan.rawValue
        let debt: String? = LockedRole.debt.rawValue
        var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate {
            $0.linkID == link && ($0.category?.lockedRoleRaw == loan || $0.category?.lockedRoleRaw == debt)
        })
        descriptor.fetchLimit = 1
        return (Log.store.attempt("Counting the Loan and Debt links") { try context.fetchCount(descriptor) } ?? 0) > 0
    }

    /// Whether this is a part of a Split: an Expense or Income sharing a link with no Loan or Debt on it. It is edited
    /// like any ordinary transaction, and nothing it holds is ever shared with the other parts. Only a linked Expense or
    /// Income reads the store.
    var isSplitPart: Bool { isLinkedExpenseOrIncome && !sharesLinkWithLoanOrDebt }

    /// ``isSplitPart``, with the links of every Loan and Debt read once beforehand (``loanOrDebtLinks(in:)``).
    func isSplitPart(loanOrDebtLinks: Set<UUID>) -> Bool {
        guard isLinkedExpenseOrIncome, let link = linkID else { return false }
        return !loanOrDebtLinks.contains(link)
    }

    /// Splits this transaction as `draft` has it, in `context`: it keeps its identity, creation time and Recurring
    /// attachment and takes the draft's remainder and fields, and each new part is made as a copy in its wallet and
    /// Card with its own fields. All the parts share a link, so they show as Related transactions. Returns the new
    /// parts. A Reimbursement goes to the part the draft assigns it to; those assigned to the original stay. Saves.
    /// Nothing changes when the transaction can't be split or the draft breaks a split rule.
    @discardableResult
    func split(_ draft: SplitDraft, in context: ModelContext) throws -> [Transaction] {
        guard canBeSplit else { throw SplitRuleError.notSplittable }
        try draft.validate()
        let link = linkID ?? UUID()
        draft.original.apply(to: self)
        linkID = link
        // Typing over the original so the total changes confirms an Estimated transaction, as editing it does. Only
        // moving parts of it elsewhere leaves the estimate as it was.
        if draft.total != draft.was {
            clearEstimate()
        }
        let created = draft.parts.map { part -> Transaction in
            let transaction = Transaction(amount: Money(cents: 0), day: part.day, wallet: nil, category: nil)
            context.insert(transaction)
            part.apply(to: transaction)
            transaction.wallet = wallet
            transaction.card = card
            transaction.isExcludedFromReport = isExcludedFromReport
            transaction.linkID = link
            return transaction
        }
        for entry in draft.reimbursements {
            if case .part(let index)? = entry.part {
                entry.reimbursement.expense = created[index]
            }
        }
        for part in [self] + created {
            part.recountReimbursements()
        }
        try context.save()
        return created
    }

    /// Undo split: merges every part of the split back into the oldest one, the original, which takes the sum of their
    /// amounts and loses its link, and every part's Reimbursements. The other parts are removed. A part in Recently Deleted is left where it is and
    /// isn't counted. Returns the original. Saves. Throws when there is no other part to merge.
    @discardableResult
    func undoSplit(in context: ModelContext) throws -> Transaction {
        let parts = try context.fetch(linkedTransactions)
        guard isSplitPart, parts.contains(self), let original = parts.splitOriginal, parts.count > 1
        else { throw SplitRuleError.notSplit }
        original.amountCents = parts.reduce(0) { $0 + $1.amountCents }
        original.linkID = nil
        for part in parts where part != original {
            // Moved off first, so deleting the part doesn't take its Reimbursements with it.
            for reimbursement in part.reimbursements ?? [] {
                reimbursement.expense = original
            }
            context.delete(part)
        }
        original.recountReimbursements()
        try context.save()
        return original
    }
}

nonisolated extension Sequence where Element == Transaction {
    /// The original among the parts of one Split: the oldest, the transaction the user split from, which kept its
    /// identity. A part split off later is never older. `nil` when there are none.
    var splitOriginal: Transaction? { self.min { $0.createdAt < $1.createdAt } }
}
