import Foundation
import SwiftData

/// The saved total of one wallet for one calendar month: the net (``Transaction/netCents``) of that month's
/// transactions in the wallet outside Recently Deleted. A copy kept so a balance doesn't add up every transaction, never
/// the truth: it is counted again from the transactions whenever its month is marked dirty (``DirtyWalletMonth``), is
/// never synced, and goes with its wallet (ADR-0013).
@Model
final class WalletMonthTotal {
    /// The month as `yyyymm`.
    var monthRaw: Int = 0
    var netCents: Int = 0
    var wallet: Wallet?

    init(monthRaw: Int, netCents: Int) {
        self.monthRaw = monthRaw
        self.netCents = netCents
    }
}

/// A wallet-month whose saved total (``WalletMonthTotal``) no longer matches its transactions: one of them was made,
/// moved, changed or moved to or from Recently Deleted. Marked by ``Transaction/changeCounted(_:)`` in the same context
/// as the change, so both go into the same save (ADR-0013). A month is marked at most once until it is counted again.
@Model
final class DirtyWalletMonth {
    /// The month as `yyyymm`.
    var monthRaw: Int = 0
    var wallet: Wallet?

    init(monthRaw: Int) {
        self.monthRaw = monthRaw
    }
}
