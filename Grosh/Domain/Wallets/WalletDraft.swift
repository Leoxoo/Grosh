import Foundation
import SwiftData

/// The editable fields of a wallet, as the Add/Edit form holds them before the wallet rules check and save them.
/// A new wallet's Starting balance is given to ``Wallet/create(_:startingBalance:on:in:)`` alongside it.
nonisolated struct WalletDraft {
    var name = ""
    var symbolName = "wallet.bifold.fill"
    var color = PaletteColor.green
    var includeInTotal = true
    /// The wallet's currency. A new wallet takes the one in Settings → Currency; an existing one keeps its own.
    var currencyCode = Money.defaultCurrencyCode

    /// A new wallet in `currencyCode`.
    init(currencyCode: String = Money.defaultCurrencyCode) {
        self.currencyCode = currencyCode
    }

    @MainActor init(_ wallet: Wallet) {
        name = wallet.name
        symbolName = wallet.symbolName
        color = wallet.color
        includeInTotal = wallet.includeInTotal
        currencyCode = wallet.currencyCode
    }

    /// A new wallet's Starting balance as typed on the Keypad: the money it holds now, typed with a leading minus when
    /// it starts in debt. Nothing typed is zero.
    var startingBalanceEntry = AmountEntry(kind: .balance)

    /// The Starting balance typed, in the wallet's currency, or `nil` while the Keypad can't work it out, as when it
    /// divides by zero.
    var startingBalance: Money? {
        startingBalanceEntry.cents.map { Money(cents: $0, currencyCode: currencyCode) }
    }

    fileprivate var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    func validate() throws {
        guard !trimmedName.isEmpty else { throw WalletRuleError.missingName }
    }

    /// Checks a new wallet: a name, and a Starting balance the Keypad can work out.
    func validateNew() throws {
        try validate()
        guard startingBalance != nil else { throw WalletRuleError.invalidStartingBalance }
    }
}

/// Why a wallet change was refused.
nonisolated enum WalletRuleError: Error, Equatable {
    case missingName
    /// The Starting balance typed can't be worked out, as when it divides by zero.
    case invalidStartingBalance
}

extension WalletRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: Strings.Wallets.missingName)
        case .invalidStartingBalance: String(localized: Strings.Wallets.invalidStartingBalance)
        }
    }
}

extension Wallet {
    /// Adds a wallet at the end of the user's order and records the money it already holds as its Starting
    /// balance: its first transaction, under the locked Starting balance category and always excluded from report.
    /// Saves.
    @discardableResult
    static func create(_ draft: WalletDraft, startingOn day: CalendarDay, in context: ModelContext) throws -> Wallet {
        try draft.validateNew()
        guard let startingBalance = draft.startingBalance else { throw WalletRuleError.invalidStartingBalance }
        return try create(draft, startingBalance: startingBalance, on: day, in: context)
    }

    /// ``create(_:startingOn:in:)`` with a Starting balance given apart from the draft, as an import has it.
    @discardableResult
    static func create(
        _ draft: WalletDraft,
        startingBalance: Money,
        on day: CalendarDay,
        in context: ModelContext
    ) throws -> Wallet {
        let wallet = try insert(draft, startingBalance: startingBalance, on: day, in: context)
        try context.save()
        return wallet
    }

    /// ``create(_:startingBalance:on:in:)`` without the save, for a caller that saves once after adding many, such
    /// as an import. The Starting balance is entered at `enteredAt`, which orders it among its day's transactions.
    @discardableResult
    static func insert(
        _ draft: WalletDraft,
        startingBalance: Money,
        on day: CalendarDay,
        enteredAt: Date = .now,
        in context: ModelContext
    ) throws -> Wallet {
        try draft.validate()
        let category = try context.lockedCategory(.startingBalance)
        let wallet = try insertWithoutStartingBalance(draft, in: context)

        let starting = Transaction.insert(startingBalance, on: day, wallet: wallet, category: category, in: context)
        starting.isExcludedFromReport = true
        starting.createdAt = enteredAt
        return wallet
    }

    /// Adds a wallet at the end of the user's order with no Starting balance, for an import that brings the wallet's
    /// Starting balance as one of its rows. Doesn't save.
    @discardableResult
    static func insertWithoutStartingBalance(_ draft: WalletDraft, in context: ModelContext) throws -> Wallet {
        try draft.validate()
        let wallet = Wallet(name: draft.trimmedName, sortOrder: try context.nextSortOrder(\Wallet.sortOrder))
        context.insert(wallet)
        wallet.currencyCode = draft.currencyCode
        wallet.apply(draft)
        return wallet
    }

    func update(with draft: WalletDraft) throws {
        try draft.validate()
        apply(draft)
        try saveToStore()
    }

    private func apply(_ draft: WalletDraft) {
        name = draft.trimmedName
        symbolName = draft.symbolName
        color = draft.color
        includeInTotal = draft.includeInTotal
    }
}
