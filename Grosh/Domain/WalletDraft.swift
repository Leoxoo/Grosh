import Foundation
import SwiftData

/// The editable fields of a wallet, as the Add/Edit form holds them before the wallet rules check and save them.
/// A new wallet's Starting balance is given to ``Wallet/create(_:startingBalance:on:in:)`` alongside it.
nonisolated struct WalletDraft {
    var name = ""
    var symbolName = "wallet.bifold.fill"
    var color = PaletteColor.green
    var includeInTotal = true

    init() {}

    /// The wallet's current fields, ready to edit.
    init(_ wallet: Wallet) {
        name = wallet.name
        symbolName = wallet.symbolName
        color = wallet.color
        includeInTotal = wallet.includeInTotal
    }

    fileprivate var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Checks the draft against the wallet rules before anything is saved.
    func validate() throws {
        guard !trimmedName.isEmpty else { throw WalletRuleError.missingName }
    }
}

/// Why a wallet change was refused.
nonisolated enum WalletRuleError: Error, Equatable {
    case missingName
}

extension WalletRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "Give the wallet a name.")
        }
    }
}

extension Wallet {
    /// Adds a wallet at the end of the user's order and records the money it already holds as its Starting
    /// balance: its first transaction, under the locked Starting balance category and always excluded from report.
    /// Saves.
    @discardableResult
    static func create(
        _ draft: WalletDraft,
        startingBalance: Money,
        on day: CalendarDay,
        in context: ModelContext
    ) throws -> Wallet {
        try draft.validate()
        let category = try context.lockedCategory(.startingBalance)
        let wallet = Wallet(name: draft.trimmedName, sortOrder: try context.nextSortOrder(\Wallet.sortOrder))
        context.insert(wallet)
        wallet.apply(draft)

        let starting = Transaction(amount: startingBalance, day: day, wallet: nil, category: nil)
        starting.isExcludedFromReport = true
        context.insert(starting)
        starting.wallet = wallet
        starting.category = category
        try context.save()
        return wallet
    }

    /// Saves an edited draft. Nothing changes when the draft breaks a wallet rule.
    func update(with draft: WalletDraft) throws {
        try draft.validate()
        apply(draft)
        try modelContext?.save()
    }

    private func apply(_ draft: WalletDraft) {
        name = draft.trimmedName
        symbolName = draft.symbolName
        color = draft.color
        includeInTotal = draft.includeInTotal
    }
}
