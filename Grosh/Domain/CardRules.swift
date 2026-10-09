import Foundation
import SwiftData

/// What the user enters for a Card when adding or editing it.
nonisolated struct CardDetails {
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
    /// A Card that paid for transactions can't be deleted; merge it into another Card instead.
    case hasTransactions
}

extension CardDetails {
    /// The details a Card has now, to start editing from.
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

    /// Checks the details against the Card rules before anything is saved.
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
    static func create(_ details: CardDetails, in context: ModelContext) throws -> Card {
        try details.validate()
        let card = Card(name: details.name, kind: details.kind, payingWallet: nil, sortOrder: try nextSortOrder(in: context))
        context.insert(card)
        card.apply(details)
        return card
    }

    /// Saves edited details. Nothing changes when the details break a Card rule.
    func update(with details: CardDetails) throws {
        try details.validate()
        apply(details)
    }

    private func apply(_ details: CardDetails) {
        name = details.trimmedName
        kind = details.kind
        payingWallet = details.payingWallet
        colorName = details.color.rawValue
        lastFourDigits = details.storedLastFourDigits
        statementDay = details.statementDay
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

    /// Moves every transaction paid with this Card to `target`, then removes this Card.
    func merge(into target: Card, in context: ModelContext) throws {
        guard target != self else { throw CardRuleError.mergeIntoItself }
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
