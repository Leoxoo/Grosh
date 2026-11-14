import SwiftData
import SwiftUI

/// Every wallet's balance today (`@Environment(\.today)`), read from the saved month totals rather than from every
/// transaction, unless they can't be read (``WalletBalances/readOrCount(asOf:in:fromSavedTotals:)``, ADR-0013): what
/// Home, the Wallets list and the Wallet selector show.
///
/// Read again after each save of the view's model context (``StoreSaves``), which by then has counted the months it
/// changed, and when the day changes; between those, every draw reuses the balances read.
@propertyWrapper
struct SavedWalletBalances: DynamicProperty {
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today
    @StoreSaves private var saves
    @State private var balances = DrawingCache<Read, WalletBalances>()

    var wrappedValue: WalletBalances {
        balances.value(for: Read(context: ObjectIdentifier(context), today: today, saves: saves)) {
            WalletBalances.readOrCount(asOf: today, in: context)
        }
    }

    /// What the balances were read from.
    struct Read: Equatable {
        let context: ObjectIdentifier
        let today: CalendarDay
        let saves: Int
    }
}
