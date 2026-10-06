/// One category in the starting tree, with its subcategories.
nonisolated struct CategorySeed: Sendable {
    var name: String
    var type: CategoryType
    var symbolName: String
    var color: PaletteColor
    var lockedRole: LockedRole?
    var children: [CategorySeed] = []
}

/// The tree a fresh install starts with. This is the user's own MoneyLover tree; it is plain data so it can be
/// swapped for a generic starter set before the app ships.
nonisolated enum DefaultCategories {
    static let tree: [CategorySeed] = expenseTree + incomeTree + debtLoanTree + systemTree

    private static func expense(
        _ name: String, _ symbolName: String, _ color: PaletteColor,
        role: LockedRole? = nil, _ children: [CategorySeed] = []
    ) -> CategorySeed {
        CategorySeed(name: name, type: .expense, symbolName: symbolName, color: color, lockedRole: role, children: children)
    }

    private static func income(
        _ name: String, _ symbolName: String, _ color: PaletteColor,
        role: LockedRole? = nil, _ children: [CategorySeed] = []
    ) -> CategorySeed {
        CategorySeed(name: name, type: .income, symbolName: symbolName, color: color, lockedRole: role, children: children)
    }

    private static let expenseTree: [CategorySeed] = [
        expense("Food & Beverage", "fork.knife", .orange, [
            expense("Café", "cup.and.saucer.fill", .brown),
            expense("Restaurants", "takeoutbag.and.cup.and.straw.fill", .red),
        ]),
        expense("Products", "cart.fill", .green),
        expense("Bills & Utilities", "doc.text.fill", .gray, [
            expense("Phone Bill", "iphone", .red),
            expense("Water Bill", "drop.fill", .blue),
            expense("Electricity Bill", "bolt.fill", .yellow),
            expense("Gas Bill", "flame.fill", .orange),
            expense("Valet/Trash Bill", "trash.fill", .brown),
            expense("Internet Bill", "wifi", .teal),
            expense("Rentals", "house.fill", .indigo),
        ]),
        expense("Personal Transport", "car.fill", .yellow, [
            expense("Vehicle Maintenance", "wrench.and.screwdriver.fill", .gray),
            expense("Parking Fees", "parkingsign", .blue),
            expense("Petrol", "fuelpump.fill", .red),
        ]),
        expense("Other Transport", "bus.fill", .teal, [
            expense("Taxi", "car.side.fill", .yellow),
            expense("Public Transport", "tram.fill", .blue),
            expense("Other Fuel", "fuelpump", .orange),
        ]),
        expense("Shopping", "bag.fill", .teal, [
            expense("Accessories", "eyeglasses", .purple),
            expense("Books", "book.fill", .indigo),
            expense("Clothing", "tshirt.fill", .yellow),
            expense("Electronics", "laptopcomputer", .orange),
            expense("Footwear", "shoeprints.fill", .green),
            expense("Home Improvement", "hammer.fill", .mint),
            expense("Personal Care", "sparkles", .cyan),
            expense("Car accessories", "steeringwheel", .blue),
            expense("3D printing", "cube.fill", .gray),
        ]),
        expense("Health & Fitness", "heart.fill", .red, [
            expense("Doctor", "stethoscope", .teal),
            expense("Pharmacy", "pills.fill", .blue),
            expense("Sports", "figure.run", .green),
        ]),
        expense("Education", "graduationcap.fill", .teal),
        expense("Entertainment", "gamecontroller.fill", .blue, [
            expense("Games", "dice.fill", .green),
            expense("Movies", "film.fill", .indigo),
            expense("Cultural/Animals", "building.columns.fill", .brown),
            expense("Apps", "apps.iphone", .blue),
            expense("Streaming Service", "play.tv.fill", .red),
        ]),
        expense("Gifts & Donations", "gift.fill", .pink, [
            expense("Charity", "hand.raised.fill", .mint),
            expense("Friends & Lover", "person.2.fill", .red),
        ]),
        expense("Insurances", "shield.fill", .green, [
            expense("Car Insurance", "car.fill", .yellow),
            expense("Personal Insurance", "heart.text.square.fill", .red),
            expense("Other Insurance", "shield.lefthalf.filled", .teal),
            expense("Apartment Insurance", "house.fill", .green),
        ]),
        expense("Fees & Charges", "percent", .yellow, [
            expense("Tax Due", "building.columns", .red),
        ]),
        expense("Guns and Ammo", "scope", .gray, [
            expense("Gun accessories", "wrench.fill", .gray),
            expense("Ammo", "shippingbox.fill", .brown),
            expense("Range", "target", .orange),
        ]),
        expense("Investment", "chart.line.uptrend.xyaxis", .green),
        expense("Children & Babies", "stroller.fill", .pink),
        expense("Marriage", "heart.circle.fill", .pink),
        expense("Travel", "airplane", .blue),
        expense("Pets", "pawprint.fill", .brown),
        expense("Withdrawal", "banknote", .green),
        expense("Unknown transaction", "questionmark.circle.fill", .gray),
        expense("Other Expense", "ellipsis.circle.fill", .gray, role: .otherExpense),
        expense("Outgoing transfer", "arrow.up.right.circle.fill", .orange, role: .outgoingTransfer),
    ]

    private static let incomeTree: [CategorySeed] = [
        income("Salary", "banknote.fill", .green),
        income("Tips", "dollarsign.circle.fill", .green),
        income("Extra work", "briefcase.fill", .brown),
        income("Award", "trophy.fill", .yellow),
        income("Selling", "tag.fill", .blue),
        income("Sombodypaid", "person.crop.circle.badge.checkmark", .teal),
        income("School extra", "book.closed.fill", .blue, [
            income("VA", "globe.americas.fill", .indigo),
        ]),
        income("Cashback", "arrow.uturn.backward.circle.fill", .mint),
        income("Tax Return", "building.columns.fill", .indigo),
        income("Collect Interest", "percent", .orange),
        income("Gifts", "gift.fill", .pink),
        income("Other Income", "ellipsis.circle.fill", .gray, role: .otherIncome),
        income("Incoming transfer", "arrow.down.left.circle.fill", .blue, role: .incomingTransfer),
    ]

    private static let debtLoanTree: [CategorySeed] = [
        CategorySeed(name: "Loan", type: .debtLoan, symbolName: "arrow.up.right.square.fill", color: .orange, lockedRole: .loan),
        CategorySeed(name: "Debt", type: .debtLoan, symbolName: "arrow.down.left.square.fill", color: .purple, lockedRole: .debt),
        CategorySeed(name: "Debt Collection", type: .debtLoan, symbolName: "arrow.down.left.circle.fill", color: .green, lockedRole: .debtCollection),
        CategorySeed(name: "Repayment", type: .debtLoan, symbolName: "arrow.up.right.circle.fill", color: .red, lockedRole: .repayment),
    ]

    private static let systemTree: [CategorySeed] = [
        CategorySeed(name: "Starting balance", type: .system, symbolName: "flag.fill", color: .gray, lockedRole: .startingBalance),
    ]
}
