import Foundation

/// What a wallet picker that shows balances, as the Transfer sheet's From and To do, says about a wallet. It is always
/// the balance today, whatever day the sheet is dated: a transaction dated after today doesn't move a balance until its
/// day comes, so a balance "after" a future transfer would mislead.
extension Wallet {
    /// The small line under the picker's row naming the chosen wallet's balance on `today`, in the wallet's own
    /// currency, such as "Balance today: $987.24".
    func pickerBalanceLine(asOf today: CalendarDay, locale: Locale = .current) -> String {
        String(localized: "Balance today: \(pickerOptionBalance(asOf: today, locale: locale))")
    }

    /// The wallet's balance on `today` as its option in the picker's dropdown shows it under the wallet's name, in the
    /// wallet's own currency, such as "$987.24".
    func pickerOptionBalance(asOf today: CalendarDay, locale: Locale = .current) -> String {
        balance(asOf: today).formatted(locale: locale)
    }
}
