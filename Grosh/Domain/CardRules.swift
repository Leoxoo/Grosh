import Foundation
import SwiftData

/// The editable fields of a Card, as the Add/Edit form holds them before the Card rules check and save them.
nonisolated struct CardDraft {
    var name: String
    var kind: CardKind
    var payingWallet: Wallet?
    var color: PaletteColor = .blue
    var lastFourDigits: String?
    /// The day of the month (1–31) a Credit card's statement closes.
    var statementDay: Int?
}

/// Why a Card change was refused.
nonisolated enum CardRuleError: Error, Equatable {
    case missingName
    /// Every Card is paid from a wallet; it is only offered on that wallet's transactions.
    case missingPayingWallet
    /// Only Credit cards have a statement; a Debit card spends straight from its wallet.
    case statementDateRequiresCredit
    /// A statement date is a day of the month, 1–31.
    case statementDayOutOfRange
    /// The last digits of a card number are exactly four digits, 0–9.
    case invalidLastFourDigits
    /// Merging needs a different Card to move the transactions to.
    case mergeIntoItself
    /// A Card only merges into a Card paid from the same wallet, so its transactions keep a Card their wallet offers.
    case mergeIntoAnotherWallet
    /// An archived Card is out of the pickers; unarchive it before merging into it.
    case mergeIntoArchived
    /// A Card that paid for transactions can't be deleted; merge it into another Card instead.
    case hasTransactions
    /// A Card that paid for transactions keeps its paying wallet, so those transactions keep a Card their wallet offers.
    case payingWalletHasTransactions
}

extension CardRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "Give the Card a name.")
        case .missingPayingWallet: String(localized: "Choose the wallet this Card is paid from.")
        case .statementDateRequiresCredit: String(localized: "Only Credit cards have a statement date.")
        case .statementDayOutOfRange: String(localized: "A statement date is a day from 1 to 31.")
        case .invalidLastFourDigits: String(localized: "Enter all 4 last digits, or leave them blank.")
        case .mergeIntoItself: String(localized: "Choose another Card to merge into.")
        case .mergeIntoAnotherWallet: String(localized: "Choose a Card paid from the same wallet.")
        case .mergeIntoArchived: String(localized: "Unarchive that Card before merging into it.")
        case .hasTransactions: String(localized: "This Card paid for transactions. Merge it into another Card to remove it.")
        case .payingWalletHasTransactions: String(localized: "This Card paid for transactions, so its paying wallet can't change.")
        }
    }
}

extension CardDraft {
    /// The Card's current fields, ready to edit.
    init(_ card: Card) {
        self.init(
            name: card.name,
            kind: card.kind,
            payingWallet: card.payingWallet,
            color: card.color,
            lastFourDigits: card.lastFourDigits,
            statementDay: card.statementDay
        )
    }

    fileprivate var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The last 4 digits as stored: `nil` when left blank.
    fileprivate var storedLastFourDigits: String? {
        let trimmed = lastFourDigits?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Checks the draft against the Card rules before anything is saved.
    func validate() throws {
        guard !trimmedName.isEmpty else { throw CardRuleError.missingName }
        guard payingWallet != nil else { throw CardRuleError.missingPayingWallet }
        if let digits = storedLastFourDigits {
            guard digits.count == 4, digits.allSatisfy({ ("0"..."9").contains($0) }) else {
                throw CardRuleError.invalidLastFourDigits
            }
        }
        if let statementDay {
            guard kind == .credit else { throw CardRuleError.statementDateRequiresCredit }
            guard (1...31).contains(statementDay) else { throw CardRuleError.statementDayOutOfRange }
        }
    }
}

extension Card {
    /// Adds a Card.
    @discardableResult
    static func create(_ draft: CardDraft, in context: ModelContext) throws -> Card {
        try draft.validate()
        let card = Card(name: draft.name, kind: draft.kind, payingWallet: nil, sortOrder: try nextSortOrder(in: context))
        context.insert(card)
        card.apply(draft)
        return card
    }

    /// Saves an edited draft. Nothing changes when the draft breaks a Card rule.
    func update(with draft: CardDraft) throws {
        try draft.validate()
        guard draft.payingWallet == payingWallet || !hasTransactions else {
            throw CardRuleError.payingWalletHasTransactions
        }
        apply(draft)
    }

    private func apply(_ draft: CardDraft) {
        name = draft.trimmedName
        kind = draft.kind
        payingWallet = draft.payingWallet
        colorName = draft.color.rawValue
        lastFourDigits = draft.storedLastFourDigits
        statementDay = draft.statementDay
    }

    var color: PaletteColor { PaletteColor(rawValue: colorName) ?? .blue }

    /// The position after every Card already in the store, archived ones included.
    private static func nextSortOrder(in context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Card>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map { $0.sortOrder + 1 } ?? 0
    }

    /// The order Cards are listed in everywhere: the order they were added.
    static let userOrder: [SortDescriptor<Card>] = [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]

    /// The Cards a transaction in `wallet` can be paid with: the unarchived Cards whose paying wallet it is.
    /// `current` (the Card the transaction already has) is kept at the end when it isn't one of them, for
    /// instance because it was archived since, so editing a past transaction still shows its Card.
    /// When the user switches the transaction to another wallet, drop its Card before asking again.
    static func pickerChoices(for wallet: Wallet?, keeping current: Card?) -> [Card] {
        let offered = (wallet?.cards ?? []).filter { !$0.isArchived }.sorted(using: userOrder)
        guard let current, !offered.contains(current) else { return offered }
        return offered + [current]
    }

    /// Retires the Card: it leaves every picker but stays on the transactions it paid for.
    func archive() {
        isArchived = true
    }

    /// Brings an archived Card back into the pickers.
    func unarchive() {
        isArchived = false
    }

    /// The Cards this one can be merged into: the other unarchived Cards paid from the same wallet, in the
    /// user's order. Its transactions stay in their wallet, so they keep a Card that wallet offers.
    var mergeTargets: [Card] {
        Card.pickerChoices(for: payingWallet, keeping: nil).filter { $0 != self }
    }

    /// Moves every transaction paid with this Card to `target`, then removes this Card.
    func merge(into target: Card, in context: ModelContext) throws {
        guard target != self else { throw CardRuleError.mergeIntoItself }
        guard target.payingWallet == payingWallet else { throw CardRuleError.mergeIntoAnotherWallet }
        guard !target.isArchived else { throw CardRuleError.mergeIntoArchived }
        for transaction in transactions ?? [] {
            transaction.card = target
        }
        context.delete(self)
    }

    /// Whether any transaction was paid with this Card, so it can only go away by merging.
    var hasTransactions: Bool { !(transactions ?? []).isEmpty }

    /// Removes a Card that never paid for anything. A Card with transactions must be merged instead.
    func delete(in context: ModelContext) throws {
        guard !hasTransactions else { throw CardRuleError.hasTransactions }
        context.delete(self)
    }

    /// The day this Credit card's statement closes in the given month, or `nil` when it has no statement date.
    /// A statement date past the month's end (the 31st in April) falls on the month's last day.
    func statementClosingDay(year: Int, month: Int) -> CalendarDay? {
        guard let statementDay else { return nil }
        let isLeapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let daysInMonth = switch month {
        case 2: isLeapYear ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
        return CalendarDay(year: year, month: month, day: min(statementDay, daysInMonth))
    }
}
