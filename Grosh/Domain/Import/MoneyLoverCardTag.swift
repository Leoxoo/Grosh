import Foundation

/// A hashtag the user's MoneyLover notes name a Card with, and the Card it becomes on import.
nonisolated struct MoneyLoverCardTag: Hashable, Sendable {
    /// Lowercase, with its `#`.
    let tag: String
    let cardName: String
    let kind: CardKind
    let color: PaletteColor
}

extension MoneyLoverCardTag {
    /// The user's card hashtags, in the order their Cards are listed. Data, not logic: it is the user's own and
    /// changes with their cards.
    static let all: [MoneyLoverCardTag] = [
        MoneyLoverCardTag(tag: "#checking", cardName: "Navy Federal Debit", kind: .debit, color: .blue),
        MoneyLoverCardTag(tag: "#nfcu", cardName: "Navy Federal", kind: .credit, color: .indigo),
        MoneyLoverCardTag(tag: "#wellsfargo", cardName: "Wells Fargo", kind: .credit, color: .red),
        MoneyLoverCardTag(tag: "#applecard", cardName: "Apple Card", kind: .credit, color: .gray),
        MoneyLoverCardTag(tag: "#boa", cardName: "Bank of America", kind: .credit, color: .pink),
        MoneyLoverCardTag(tag: "#citi", cardName: "Citi", kind: .credit, color: .cyan),
        MoneyLoverCardTag(tag: "#amex", cardName: "Amex", kind: .credit, color: .teal),
        MoneyLoverCardTag(tag: "#chase", cardName: "Chase", kind: .credit, color: .purple),
        MoneyLoverCardTag(tag: "#discover", cardName: "Discover", kind: .credit, color: .orange),
        MoneyLoverCardTag(tag: "#petal", cardName: "Petal", kind: .credit, color: .mint),
        MoneyLoverCardTag(tag: "#paypal", cardName: "PayPal", kind: .credit, color: .yellow),
    ]

    /// The wallet every imported Card is paid from, when the export has it.
    static let payingWalletName = "Checking (Navy Federal)"

    /// The first card hashtag in `note`, ignoring case, and the note without it, its spaces tidied. A longer
    /// hashtag (`#chasefreedom`) isn't `#chase`. Every other hashtag, another card's included, stays in the note.
    /// `nil` for a note without a card hashtag.
    static func first(in note: String) -> (tag: MoneyLoverCardTag, note: String)? {
        for match in note.matches(of: #/\#\w+/#) {
            let text = note[match.range].lowercased()
            guard let tag = all.first(where: { $0.tag == text }) else { continue }
            let before = note[..<match.range.lowerBound].trimmingSuffix(while: \.isSpaceOrTab)
            let after = note[match.range.upperBound...].trimmingPrefix(while: \.isSpaceOrTab)
            let gap = before.isEmpty || after.isEmpty || before.last?.isNewline == true || after.first?.isNewline == true
                ? "" : " "
            return (tag, String(before) + gap + String(after))
        }
        return nil
    }
}

private extension Character {
    nonisolated var isSpaceOrTab: Bool { self == " " || self == "\t" }
}

private extension Substring {
    nonisolated func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
        var trimmed = self
        while let last = trimmed.last, predicate(last) {
            trimmed.removeLast()
        }
        return trimmed
    }
}
