/// How someone's MoneyLover notes name their cards, and the Cards those become on import: the hashtags, and the wallet
/// the Cards are paid from. MoneyLover has no Cards, so this is the importing person's own data, which the import is
/// given (``MoneyLoverImport/replaceAllData(with:cards:in:now:)``) rather than knowing it.
nonisolated struct MoneyLoverCardMapping: Hashable, Sendable {
    /// The wallet every Card made from a hashtag is paid from, when the export has it. Without it, or `nil`, each Card
    /// is paid from the wallet of the first row it could be given on.
    let payingWalletName: String?
    /// The card hashtags, in the order their Cards are listed.
    let tags: [MoneyLoverCardTag]

    /// No card hashtags: every hashtag stays in its note, and only a Grosh export's `Card` column makes Cards.
    static let none = MoneyLoverCardMapping(payingWalletName: nil, tags: [])
}
