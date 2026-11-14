extension MoneyLoverCardMapping {
    /// The card hashtags of the person the app is made for, the ones Import from MoneyLover reads, all paid from one
    /// wallet. Their own data, like ``DefaultCategories``: change it with their cards, or swap it for someone else's.
    static let ownersCards = MoneyLoverCardMapping(
        payingWalletName: "Checking (Navy Federal)",
        tags: [
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
    )
}
