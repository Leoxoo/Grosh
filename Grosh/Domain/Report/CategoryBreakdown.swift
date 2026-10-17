extension Category {
    /// The parent category this one rolls up into, or the category itself when it is a parent.
    var parentOrSelf: Category { parent ?? self }
}

/// One parent category's total for a side of the Report: what counts toward the side under the category, its
/// subcategories included.
struct CategoryTotal {
    let category: Category
    let total: Money
}

/// A side's period total split by parent category, for the Category report's donut and the Breakdown list. A
/// subcategory's amount adds into its parent, and anything filed directly under a parent counts there too.
struct CategoryBreakdown {
    /// How many parent categories get a donut slice of their own before the rest share Everything else.
    static let ownSliceCount = 5

    /// One donut slice: a parent category, or the smaller ones together.
    enum Slice {
        case category(CategoryTotal)
        case everythingElse(Money)

        /// What the slice holds.
        var amount: Money {
            switch self {
            case .category(let total): total.total
            case .everythingElse(let amount): amount
            }
        }
    }

    let side: SpentOrIncome
    /// What the side adds up to in all: every category's total, including those at or below zero.
    let total: Money
    /// Every parent category with anything counted toward the side, largest first. One whose total isn't above zero, such
    /// as one whose refunds outweigh what was spent, is listed after the ones above it.
    let categories: [CategoryTotal]
    /// The categories above zero, largest first: those that get a donut slice.
    private let aboveZero: [CategoryTotal]
    /// What the categories above zero add up to, which every share is of.
    private let shareBase: Int

    /// The breakdown of `side` in `counted`, what the period counts (``Sequence/counted(in:during:today:)``).
    init(side: SpentOrIncome, of counted: [CountedAmount]) {
        var centsByParent: [Category: Int] = [:]
        for amount in counted where amount.side == side {
            let parent = amount.category.parentOrSelf
            centsByParent[parent, default: 0] += amount.amount.cents
        }
        let categories = centsByParent
            .map { CategoryTotal(category: $0.key, total: Money(cents: $0.value)) }
            .sorted { lhs, rhs in
                lhs.total.cents != rhs.total.cents
                    ? lhs.total.cents > rhs.total.cents
                    : lhs.category.name < rhs.category.name
            }
        let aboveZero = categories.filter { $0.total.cents > 0 }

        self.side = side
        self.total = Money(cents: categories.reduce(0) { $0 + $1.total.cents })
        self.categories = categories
        self.aboveZero = aboveZero
        self.shareBase = aboveZero.reduce(0) { $0 + $1.total.cents }
    }

    /// The donut's slices, largest first. Up to `ownSliceLimit` categories above zero, each at least `minimumShare` of the
    /// categories above zero, get a slice of their own. Every other category above zero, the ones too small to be shown on
    /// their own and those past the limit, shares one Everything else slice.
    func donutSlices(ownSliceLimit: Int, minimumShare: Double = 0) -> [Slice] {
        let large = aboveZero.filter { share(of: $0.total) >= minimumShare }
        let own = Array(large.prefix(ownSliceLimit))
        let ownCategories = Set(own.map(\.category))
        let rest = aboveZero.filter { !ownCategories.contains($0.category) }
        var slices = own.map(Slice.category)
        if !rest.isEmpty {
            slices.append(.everythingElse(Money(cents: rest.reduce(0) { $0 + $1.total.cents })))
        }
        return slices
    }

    /// The donut's slices as the Report shows them: the largest `ownSliceCount` categories, and Everything else.
    var slices: [Slice] {
        donutSlices(ownSliceLimit: Self.ownSliceCount)
    }

    /// The share of the categories above zero that `amount` is, as a fraction from 0 to 1; zero for an amount that isn't
    /// above zero, so the shares of the categories above zero total 1.
    func share(of amount: Money) -> Double {
        guard amount.cents > 0, shareBase > 0 else { return 0 }
        return Double(amount.cents) / Double(shareBase)
    }
}
