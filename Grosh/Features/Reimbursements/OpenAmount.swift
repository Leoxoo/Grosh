import Foundation

extension Optional where Wrapped == Money {
    /// An Owes me figure as shown: formatted, or "?" for an open amount, which isn't known yet.
    var formattedOrUnknown: String {
        map { $0.formatted() } ?? String(localized: Strings.OwesMe.unknownAmount)
    }
}
