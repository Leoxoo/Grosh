import Foundation

extension Wallet {
    /// The wallet's balance on `today` as a line of text in the wallet's own currency, such as "Balance today: $987.24".
    /// Pass the real today, whatever day a transaction or transfer is dated: one dated after today doesn't move a
    /// balance until its day comes, so a balance "after" it would mislead.
    func balanceLine(asOf today: CalendarDay, locale: Locale = .current) -> String {
        String(localized: "Balance today: \(balance(asOf: today).formatted(locale: locale))")
    }
}
