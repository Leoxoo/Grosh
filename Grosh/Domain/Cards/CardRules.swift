import Foundation
import SwiftData

/// The editable fields of a Card, as the Add/Edit form holds them before the Card rules check and save them.
nonisolated struct CardDraft {
    var name: String
    var kind: CardKind
    var payingWallet: Wallet?
    var color: PaletteColor = .blue
    var lastFourDigits: String?
    /// Whether the Card has a statement date. Only a Credit card offers one (``offersStatementDate``), and this choice
    /// and ``statementDayChoice`` are remembered while the Kind is flipped back and forth.
    var hasStatementDate: Bool
    /// The day of the month (1–31) the statement closes, while ``hasStatementDate``.
    var statementDayChoice: Int
    /// The Card's cropped image as JPEG data. Set it with ``setImage(_:)``, which also sets the color.
    var imageData: Data?
    /// The rewards catalog entry the Card is linked to, or `nil` for none. Changing it to another entry is Change
    /// catalog card: the Card keeps its name, image, wallet, Statement date and transactions.
    var catalogCard: CatalogCard?
    /// What one point or mile is worth, in cents, for a points or miles Card. 1¢ unless the user changes it.
    var pointValueCents: Double = 1
    /// What the user set a Custom card to earn, which its rate editor sets; a linked Card earns what its entry does.
    private(set) var ownRewardKind: RewardKind?
    /// How many Edited rates linking the Card to another entry removes (Change catalog card), for its confirmation.
    private(set) var editedRatesRemovedByChange = 0

    init(
        name: String, kind: CardKind, payingWallet: Wallet?, color: PaletteColor = .blue, lastFourDigits: String? = nil,
        statementDay: Int? = nil, imageData: Data? = nil
    ) {
        self.name = name
        self.kind = kind
        self.payingWallet = payingWallet
        self.color = color
        self.lastFourDigits = lastFourDigits
        hasStatementDate = statementDay != nil
        statementDayChoice = statementDay ?? 1
        self.imageData = imageData
    }
}

/// Why a Card change was refused.
nonisolated enum CardRuleError: RuleRefusal, Equatable {
    case missingName
    /// Every Card is paid from a wallet; it is only offered on that wallet's transactions.
    case missingPayingWallet
    /// A statement date is a day of the month, 1–31.
    case statementDayOutOfRange
    /// The last digits of a card number are exactly four digits, 0–9.
    case invalidLastFourDigits
    /// Merging needs a different Card to move the transactions to.
    case mergeIntoItself
    /// A Point value is a number of cents above zero.
    case pointValueOutOfRange
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
        case .missingName: String(localized: Strings.Cards.missingName)
        case .missingPayingWallet: String(localized: Strings.Cards.missingPayingWallet)
        case .statementDayOutOfRange: String(localized: Strings.Cards.statementDayOutOfRange)
        case .invalidLastFourDigits: String(localized: Strings.Cards.invalidLastFourDigits)
        case .pointValueOutOfRange: String(localized: Strings.Cards.pointValueOutOfRange)
        case .mergeIntoItself: String(localized: Strings.Cards.mergeIntoItself)
        case .mergeIntoAnotherWallet: String(localized: Strings.Cards.mergeIntoAnotherWallet)
        case .mergeIntoArchived: String(localized: Strings.Cards.mergeIntoArchived)
        case .hasTransactions: String(localized: Strings.Cards.hasTransactions)
        case .payingWalletHasTransactions: String(localized: Strings.Cards.payingWalletHasTransactions)
        }
    }
}

nonisolated extension CardDraft {
    /// The Card as its editor starts: its linked entry from `catalog`, or as the Card last saw it when `catalog` no
    /// longer has it.
    @MainActor
    init(_ card: Card, catalog: RewardsCatalog) {
        self.init(
            name: card.name,
            kind: card.kind,
            payingWallet: card.payingWallet,
            color: card.color,
            lastFourDigits: card.lastFourDigits,
            statementDay: card.statementDay,
            imageData: card.imageData
        )
        let rewards = CardRewards(of: card, in: catalog)
        catalogCard = rewards.entry
        pointValueCents = card.pointValueCents
        ownRewardKind = card.ownRewardKind
        editedRatesRemovedByChange = rewards.entry == nil ? 0 : rewards.enteredRates.count
    }

    /// A new Card, as Add Card starts it: a Credit card with no name yet.
    static var new: CardDraft { CardDraft(name: "", kind: .credit, payingWallet: nil) }

    /// A new Card linked to `entry`, as Add Card starts it once the user picks that entry: named as the catalog names
    /// it.
    static func new(from entry: CatalogCard) -> CardDraft {
        var draft = CardDraft(name: entry.name, kind: .credit, payingWallet: nil)
        draft.catalogCard = entry
        return draft
    }

    /// Whether the Card has a Point value: one that earns points or miles, as its entry does or a Custom card was set to.
    var offersPointValue: Bool { (catalogCard?.rewardKind ?? ownRewardKind)?.earnsPoints == true }

    /// Whether the Card can have a statement date: only a Credit card has a statement; a Debit card spends straight
    /// from its wallet.
    var offersStatementDate: Bool { kind == .credit }

    /// The day of the month (1–31) the Card's statement closes, as it is saved: only a Credit card with a statement
    /// date has one.
    var statementDay: Int? { offersStatementDate && hasStatementDate ? statementDayChoice : nil }

    /// Starts a Card with no paying wallet in the first of `wallets`, the user's wallets in their order.
    mutating func startPaying(from wallets: [Wallet]) {
        if payingWallet == nil {
            payingWallet = wallets.first
        }
    }

    /// Sets the last 4 digits from what was typed, keeping only the first four digits 0–9.
    mutating func setLastFourDigits(typed: String) {
        lastFourDigits = String(typed.filter { ("0"..."9").contains($0) }.prefix(4))
    }

    /// Sets or removes the Card's image. A Card with an image takes its color from the image's average color, and
    /// removing the image keeps that color.
    mutating func setImage(_ data: Data?) {
        imageData = data
        if let data, let average = CroppedPhoto.averagePaletteColor(of: data) {
            color = average
        }
    }

    fileprivate var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The last 4 digits as stored: `nil` when left blank.
    fileprivate var storedLastFourDigits: String? {
        let trimmed = lastFourDigits?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func validate() throws {
        guard !trimmedName.isEmpty else { throw CardRuleError.missingName }
        guard payingWallet != nil else { throw CardRuleError.missingPayingWallet }
        if let digits = storedLastFourDigits {
            guard digits.count == 4, digits.allSatisfy({ ("0"..."9").contains($0) }) else {
                throw CardRuleError.invalidLastFourDigits
            }
        }
        if let statementDay {
            guard (1...31).contains(statementDay) else { throw CardRuleError.statementDayOutOfRange }
        }
        guard pointValueCents.isFinite, pointValueCents > 0 else { throw CardRuleError.pointValueOutOfRange }
    }
}

extension Card {
    /// Adds a Card at the end of the user's order. Saves.
    @discardableResult
    static func create(_ draft: CardDraft, in context: ModelContext) throws -> Card {
        try draft.validate()
        let card = try insert(draft, in: context)
        try context.save()
        return card
    }

    /// ``create(_:in:)`` without checking the draft against the Card rules or saving, for a caller that makes
    /// its own drafts and saves once after adding many, such as an import.
    @discardableResult
    static func insert(_ draft: CardDraft, in context: ModelContext) throws -> Card {
        let card = Card(name: draft.name, kind: draft.kind, payingWallet: nil, sortOrder: try context.nextSortOrder(\Card.sortOrder))
        context.insert(card)
        try card.apply(draft)
        return card
    }

    func update(with draft: CardDraft) throws {
        try draft.validate()
        guard try draft.payingWallet == payingWallet || !hasTransactions() else {
            throw CardRuleError.payingWalletHasTransactions
        }
        try apply(draft)
        try saveToStore()
    }

    private func apply(_ draft: CardDraft) throws {
        name = draft.trimmedName
        kind = draft.kind
        payingWallet = draft.payingWallet
        color = draft.color
        lastFourDigits = draft.storedLastFourDigits
        statementDay = draft.statementDay
        imageData = draft.imageData
        pointValueCents = draft.pointValueCents
        try keepLink(to: draft.catalogCard)
    }

    // MARK: Rewards catalog

    /// Links the Card to `entry`, or unlinks it with `nil`, and keeps the entry as the Card sees it now. Linking to
    /// another entry is Change catalog card: the Card keeps its name, image, wallet, Statement date and transactions.
    /// Saves.
    func link(to entry: CatalogCard?) throws {
        try keepLink(to: entry)
        try saveToStore()
    }

    private func keepLink(to entry: CatalogCard?) throws {
        if entry?.id != catalogCardID {
            // Change catalog card removes what was set for the old entry. Unlinking keeps the rates the user entered,
            // which make it a Custom card earning what the entry did, but drops their removals of the catalog's.
            if entry == nil, catalogCardID != nil, ownRewardKindRaw == nil {
                ownRewardKindRaw = lastCatalogEntry?.rewardKind.rawValue
            }
            let kept = entry == nil ? enteredRates.filter { !$0.isRemoval } : catalogCardID == nil ? enteredRates : []
            try keepEnteredRates(kept)
        }
        catalogCardID = entry?.id
        let snapshot = entry.flatMap(Self.snapshot(of:))
        if catalogSnapshot != snapshot {
            catalogSnapshot = snapshot
        }
    }

    /// The linked entry as the Card last saw it, or `nil` when it was never linked or the entry can't be read. Decoded
    /// on each read: ``CardRewards`` reads it only for a Card whose entry the catalog no longer has.
    var lastCatalogEntry: CatalogCard? {
        catalogSnapshot.flatMap { snapshot in
            Log.store.attempt("Reading a Card's last rewards catalog entry") {
                try JSONDecoder().decode(CatalogCard.self, from: snapshot)
            }
        }
    }

    private static func snapshot(of entry: CatalogCard) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return Log.store.attempt("Keeping a Card's rewards catalog entry") { try encoder.encode(entry) }
    }

    /// Keeps, on each linked Card whose entry `catalog` has, that entry as it is now, so the Card still has its rates
    /// should a newer catalog no longer have it (ADR-0014). Run when the store opens; changes nothing on Cards that
    /// already have it. Saves when it changed something.
    static func keepCatalogEntries(from catalog: RewardsCatalog, in context: ModelContext) throws {
        let linked = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.catalogCardID != nil }))
        for card in linked {
            if let id = card.catalogCardID, let entry = catalog.card(id) {
                try card.keepLink(to: entry)
            }
        }
        if context.hasChanges {
            try context.save()
        }
    }

    /// The order Cards are listed in everywhere: the order they were added.
    static let userOrder: [SortDescriptor<Card>] = [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]

    /// Every Card in the user's order, archived ones included, as a filter offers them. A Card whose paying wallet is
    /// in Recently Deleted waits out of sight with it: it is left out, and comes back when the wallet is restored.
    static var listed: FetchDescriptor<Card> {
        FetchDescriptor(predicate: #Predicate { $0.payingWallet?.deletedAt == nil }, sortBy: userOrder)
    }

    /// The unarchived Cards in the user's order, as Account → Cards lists them first. Like ``listed``, it leaves out
    /// the Cards whose paying wallet is in Recently Deleted.
    static var unarchived: FetchDescriptor<Card> {
        FetchDescriptor(predicate: #Predicate { !$0.isArchived && $0.payingWallet?.deletedAt == nil }, sortBy: userOrder)
    }

    /// The archived Cards in the user's order, as Account → Cards lists them below the others. Like ``listed``, it
    /// leaves out the Cards whose paying wallet is in Recently Deleted.
    static var archived: FetchDescriptor<Card> {
        FetchDescriptor(predicate: #Predicate { $0.isArchived && $0.payingWallet?.deletedAt == nil }, sortBy: userOrder)
    }

    /// The Cards a transaction in `wallet` can be paid with: the unarchived Cards whose paying wallet it is.
    /// `current` (the Card the transaction already has) is kept at the end when it isn't one of them, for
    /// instance because it was archived since, so editing a past transaction still shows its Card.
    /// When the user switches the transaction to another wallet, drop its Card before asking again.
    static func pickerChoices(for wallet: Wallet?, keeping current: Card?) -> [Card] {
        let offered = (wallet?.cards ?? []).filter { !$0.isArchived }.sorted(using: userOrder)
        guard let current, !offered.contains(current) else { return offered }
        return offered + [current]
    }

    /// Retires the Card: it leaves every picker but stays on the transactions it paid for. Saves.
    func archive() throws {
        isArchived = true
        try saveToStore()
    }

    /// Brings an archived Card back into the pickers. Saves.
    func unarchive() throws {
        isArchived = false
        try saveToStore()
    }

    /// The Cards this one can be merged into: the other unarchived Cards paid from the same wallet, in the
    /// user's order. Its transactions stay in their wallet, so they keep a Card that wallet offers.
    var mergeTargets: [Card] {
        Card.pickerChoices(for: payingWallet, keeping: nil).filter { $0 != self }
    }

    /// Moves every transaction and Recurring transaction paid with this Card to `target`, then removes this Card. Saves.
    func merge(into target: Card) throws {
        let context = try storeContext()
        guard target != self else { throw CardRuleError.mergeIntoItself }
        guard target.payingWallet == payingWallet else { throw CardRuleError.mergeIntoAnotherWallet }
        guard !target.isArchived else { throw CardRuleError.mergeIntoArchived }
        for transaction in transactions ?? [] {
            transaction.card = target
        }
        for recurring in recurringTransactions ?? [] {
            recurring.card = target
        }
        context.delete(self)
        try context.save()
    }

    /// Whether any transaction was paid with this Card, or a Recurring transaction is set to pay with it, so it can
    /// only go away by merging. Transactions in Recently Deleted count too, so they still have their Card when restored.
    /// Counted in the store rather than by loading the Card's transactions, which run into thousands for a main Card.
    func hasTransactions() throws -> Bool {
        let context = try storeContext()
        let id = persistentModelID
        var paid = FetchDescriptor<Transaction>(predicate: #Predicate { $0.card?.persistentModelID == id })
        paid.fetchLimit = 1
        var recurring = FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.card?.persistentModelID == id })
        recurring.fetchLimit = 1
        return try context.fetchCount(paid) > 0 || context.fetchCount(recurring) > 0
    }

    /// Removes a Card that never paid for anything. A Card with transactions must be merged instead. Saves.
    func delete() throws {
        let context = try storeContext()
        guard try !hasTransactions() else { throw CardRuleError.hasTransactions }
        context.delete(self)
        try context.save()
    }
}
