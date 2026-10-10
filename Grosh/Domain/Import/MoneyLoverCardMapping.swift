/// How the user's MoneyLover notes name their cards, and the Cards those become on import, all paid from one wallet.
/// This is the user's own data, like ``DefaultCategories``: plain data, kept apart from the import's logic, to change
/// with their cards or be swapped for someone else's.
nonisolated enum MoneyLoverCardMapping {
    /// The wallet every imported Card is paid from, when the export has it.
    static let payingWalletName = "Checking (Navy Federal)"

    /// The card hashtags, in the order their Cards are listed.
    static let tags: [MoneyLoverCardTag] = [
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
}
