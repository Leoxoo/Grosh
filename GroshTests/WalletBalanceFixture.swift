import SwiftData
@testable import Grosh

/// Shorthands the tests read balances and lists through. Each goes through the one implementation the app uses
/// (``WalletBalances``, ``TransactionListing``), from the wallets' own transactions rather than a screen's ledger.
extension Wallet {
    /// The wallet's balance on `today`, as ``WalletBalances`` adds it up from its transactions outside Recently
    /// Deleted.
    func balance(asOf today: CalendarDay) -> Money {
        WalletBalances((transactions ?? []).notDeleted, asOf: today).balance(of: self)
    }

    /// The Total of `wallets` on `today`, per currency, as ``WalletBalances/total(of:)`` adds it up.
    static func total(of wallets: [Wallet], asOf today: CalendarDay) -> [Money] {
        balances(of: wallets, asOf: today).total(of: wallets)
    }

    /// The balances of `wallets` on `today`, from their transactions outside Recently Deleted.
    static func balances(of wallets: [Wallet], asOf today: CalendarDay) -> WalletBalances {
        WalletBalances(wallets.flatMap { ($0.transactions ?? []).notDeleted }, asOf: today)
    }

    /// Adds a wallet named `name` with its Starting balance, as ``create(_:startingBalance:on:in:)`` does.
    @MainActor
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
}

extension TransactionListing {
    /// The Transactions tab's list of `selection` on `days` from `all`, with their ledger entries read from them.
    init(
        _ all: [Transaction], showing selection: WalletSelection, on days: DayRange,
        filter: TransactionFilter = TransactionFilter()
    ) {
        self.init(all, ledger: all.map(LedgerEntry.init), showing: selection, on: days, filter: filter)
    }
}

extension BalanceAdjustmentDraft {
    /// Adjust Balance in `wallet` on `day`, its recorded balance read from the wallet's own transactions.
    @MainActor
    init(wallet: Wallet?, day: CalendarDay, in context: ModelContext) throws {
        self.init(
            wallet: wallet, day: day, recordedBalance: wallet?.balance(asOf: day),
            defaultReasons: try Self.defaultReasons(in: context)
        )
    }

    /// Reads the recorded balance again after the wallet or the day changed, as the sheet does.
    mutating func readRecordedBalance() {
        readRecordedBalance(from: (wallet?.transactions ?? []).notDeleted)
    }
}
