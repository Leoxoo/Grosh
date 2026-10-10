import Foundation

/// A hashtag the user's MoneyLover notes name a Card with, and the Card it becomes on import
/// (``MoneyLoverCardMapping``).
nonisolated struct MoneyLoverCardTag: Hashable, Sendable {
    /// Lowercase, with its `#`.
    let tag: String
    let cardName: String
    let kind: CardKind
    let color: PaletteColor
}

extension MoneyLoverCardTag {
    /// Takes the first card hashtag of `tags`, ignoring case, out of `note`: the tag, and the note without it, its
    /// spaces tidied. A longer hashtag (`#chasefreedom`) isn't `#chase`. Every other hashtag, another card's included,
    /// stays in the note. `nil` for a note without a card hashtag.
    static func extractFirst(
        from note: String, among tags: [MoneyLoverCardTag] = MoneyLoverCardMapping.tags
    ) -> (tag: MoneyLoverCardTag, noteWithoutTag: String)? {
        for match in note.matches(of: #/\#\w+/#) {
            let text = note[match.range].lowercased()
            guard let tag = tags.first(where: { $0.tag == text }) else { continue }
            let before = note[..<match.range.lowerBound].trimmingSuffix(while: \.isSpaceOrTab)
            let after = note[match.range.upperBound...].trimmingPrefix(while: \.isSpaceOrTab)
            let atLineEdge = before.isEmpty || after.isEmpty
                || before.last?.isNewline == true || after.first?.isNewline == true
            return (tag, String(before) + (atLineEdge ? "" : " ") + String(after))
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
