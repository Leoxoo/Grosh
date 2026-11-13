import Foundation
import SwiftData

/// The saved total of one wallet for one calendar month: the net (``Transaction/netCents``) of that month's
/// transactions in the wallet outside Recently Deleted. A copy kept so a balance doesn't add up every transaction, never
/// the truth: it is counted again from the transactions whenever its month is marked dirty (``DirtyWalletMonth``), is
/// never synced (``GroshStore/localOnly``), and goes with its wallet (ADR-0013).
@Model
final class WalletMonthTotal {
    /// The ``CalendarMonth`` as `yyyymm`.
    private(set) var monthRaw: Int = 0
    var netCents: Int = 0
    private(set) var wallet: Wallet?

    private init(month: CalendarMonth, netCents: Int) {
        self.monthRaw = month.rawValue
        self.netCents = netCents
    }

    var month: CalendarMonth { CalendarMonth(rawValue: monthRaw) }

    /// Makes `wallet`'s total of `netCents` for `month` in `context`. It is inserted before its wallet is set:
    /// SwiftData relates two models only once both are in the same context. Doesn't save.
    @discardableResult
    static func insert(_ netCents: Int, for month: CalendarMonth, of wallet: Wallet, in context: ModelContext)
        -> WalletMonthTotal
    {
        let total = WalletMonthTotal(month: month, netCents: netCents)
        context.insert(total)
        total.wallet = wallet
        return total
    }
}

/// The format the store's saved month totals (``WalletMonthTotal``) were counted in. One per store, never synced
/// (``GroshStore/localOnly``). The totals are rebuilt from the transactions when there is none, as in a store from
/// before the app kept them, or when its version isn't the app's (ADR-0013).
@Model
final class WalletMonthTotalFormat {
    var version: Int = 0

    init(version: Int) {
        self.version = version
    }
}

/// A wallet-month whose saved total (``WalletMonthTotal``) no longer matches its transactions: one of them was made,
/// moved, changed or moved to or from Recently Deleted. Marked by ``Transaction/changeCounted(_:)`` in the same context
/// as the change, so both go into the same save, and never synced (``GroshStore/localOnly``, ADR-0013). A month is
/// marked at most once until it is counted again.
@Model
final class DirtyWalletMonth {
    /// The ``CalendarMonth`` as `yyyymm`.
    private(set) var monthRaw: Int = 0
    private(set) var wallet: Wallet?

    private init(month: CalendarMonth) {
        self.monthRaw = month.rawValue
    }

    var month: CalendarMonth { CalendarMonth(rawValue: monthRaw) }

    /// Marks `wallet`'s `month` dirty in `context`, inserted before its wallet is set. Doesn't save.
    @discardableResult
    static func insert(_ month: CalendarMonth, of wallet: Wallet, in context: ModelContext) -> DirtyWalletMonth {
        let mark = DirtyWalletMonth(month: month)
        context.insert(mark)
        mark.wallet = wallet
        return mark
    }
}
