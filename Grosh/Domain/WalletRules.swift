import Foundation
import SwiftData

extension Wallet {
    /// The order the user set by dragging. Every list and picker of wallets uses it.
    static let userOrder: [SortDescriptor<Wallet>] = [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]

    /// Unarchived wallets in the user's order: what Home and every wallet picker show.
    static var unarchived: FetchDescriptor<Wallet> {
        FetchDescriptor(predicate: #Predicate { !$0.isArchived }, sortBy: userOrder)
    }

    /// Applies a drag in `ordered` (a list in the user's order) by renumbering the wallets in their new order.
    static func move(_ ordered: [Wallet], fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { ordered[$0] }
        var reordered = ordered.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = destination - source.count(in: 0..<destination)
        reordered.insert(contentsOf: moving, at: insertionIndex)
        for (position, wallet) in reordered.enumerated() {
            wallet.sortOrder = position
        }
    }

    /// The position after every wallet already in the store, archived ones included.
    static func nextSortOrder(in context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map { $0.sortOrder + 1 } ?? 0
    }

    /// Adds a wallet named `name` with its Starting balance, as ``create(_:startingBalance:on:in:)`` does.
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

    /// Retires the wallet: it leaves the Total and every picker, but keeps all of its transactions.
    func archive() {
        isArchived = true
    }

    /// Brings an archived wallet back into its place in the user's order.
    func unarchive() {
        isArchived = false
    }

    /// The wallet's balance on `today`: the sum of its transactions dated today or earlier.
    /// Transactions dated after today belong to Future and don't count yet.
    func balance(asOf today: CalendarDay) -> Money {
        let cents = (transactions ?? [])
            .filter { $0.dayRaw <= today.rawValue }
            .reduce(0) { $0 + $1.amountCents }
        return Money(cents: cents, currencyCode: currencyCode)
    }

    /// Whether the wallet counts toward the Total: unarchived and marked "Include in total".
    var countsInTotal: Bool { !isArchived && includeInTotal }

    /// The Total on `today`: the combined balance of every unarchived wallet marked "Include in total".
    static func total(of wallets: [Wallet], asOf today: CalendarDay) -> Money {
        let cents = wallets
            .filter(\.countsInTotal)
            .reduce(0) { $0 + $1.balance(asOf: today).cents }
        return Money(cents: cents)
    }
}
