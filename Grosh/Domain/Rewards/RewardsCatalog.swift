import Foundation

/// Why the rewards catalog couldn't be read.
nonisolated enum RewardsCatalogError: GroshError, Equatable {
    /// The file is of a format this version of the app can't read: a newer pipeline renamed or retyped a field.
    case unknownFormat(Int)
}

/// The file of known credit cards and what each earns, built outside the app from issuers' pages by the rewards
/// pipeline (`tools/rewards-catalog/pipeline/publish.py`) and shipped with it as `Grosh/Resources/rewards-catalog.json`,
/// a copy of the file publish writes. Until rules are reviewed and published, the shipped file has no cards. Nothing is
/// fetched while the app runs (ADR-0013). Fields the app doesn't know are ignored, so a newer pipeline can add some
/// without a new ``formatVersion``.
nonisolated struct RewardsCatalog: Codable, Sendable {
    /// The format this app reads. The pipeline raises it when a field is renamed or retyped.
    static let formatVersion = 1

    var formatVersion: Int
    /// The day the catalog last changed, as `yyyy-MM-dd`.
    var publishedAt: String?
    var cards: [CatalogCard]

    static let empty = RewardsCatalog(formatVersion: formatVersion, publishedAt: nil, cards: [])

    private init(formatVersion: Int, publishedAt: String?, cards: [CatalogCard]) {
        self.formatVersion = formatVersion
        self.publishedAt = publishedAt
        self.cards = cards
    }

    /// Reads a catalog file. Throws ``RewardsCatalogError/unknownFormat(_:)`` for a format this app can't read.
    init(data: Data) throws {
        struct Format: Decodable { var formatVersion: Int }
        let format = try JSONDecoder().decode(Format.self, from: data).formatVersion
        guard format == Self.formatVersion else { throw RewardsCatalogError.unknownFormat(format) }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    /// The catalog in the app's bundle.
    static func bundled(from bundle: Bundle = .main) throws -> RewardsCatalog {
        guard let url = bundle.url(forResource: "rewards-catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try RewardsCatalog(data: Data(contentsOf: url))
    }

    /// The catalog the app ships, read once. When it can't be read, which a build should never ship, it is empty:
    /// linked Cards then show the rates their entry last had.
    static let shipped: RewardsCatalog = Log.store.attempt("Reading the rewards catalog") { try bundled() } ?? .empty

    /// The entry with `id`, or `nil` when this catalog doesn't have it.
    func card(_ id: String) -> CatalogCard? {
        cards.first { $0.id == id }
    }

    /// The entries whose name or issuer has every word of `text`, ignoring case and accents, by issuer then name.
    /// Every entry for blank text.
    func search(_ text: String) -> [CatalogCard] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return cards
            .filter { card in
                let searched = "\(card.issuer) \(card.name)"
                return words.allSatisfy { searched.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            .sorted { ($0.issuer, $0.name) < ($1.issuer, $1.name) }
    }
}

/// How a catalog card states what it earns.
nonisolated enum RewardKind: String, Codable, Sendable {
    case cashback, points, miles

    /// Whether its rates are points or miles per dollar, worth the Card's Point value each.
    var earnsPoints: Bool { self != .cashback }
}

/// One card in the rewards catalog.
nonisolated struct CatalogCard: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var issuer: String
    var network: String?
    var isBusiness: Bool
    /// In dollars a year.
    var annualFee: Double?
    var rewardKind: RewardKind
    var rewardProgram: String?
    var baseEarnRate: Double?
    var discontinued: Bool
    var sourceUrl: String?
    var verifiedAt: String?
    var cardConditions: [String]
    /// Whether its Bonuses add up: each on top of the Base rate.
    var bonusesStack: Bool
    var rules: [CatalogRule]
}

/// One rate a catalog card earns and where, with the issuer's sentence that states it.
nonisolated struct CatalogRule: Codable, Hashable, Sendable {
    /// The Reward categories it covers, by ``RewardCategory/id``.
    var categories: [String]
    /// Who decides the categories: `fixed`, `choose`, `top-spend` or `rotating`.
    var selection: String
    var picks: Int?
    var hasOtherChoices: Bool
    var rate: Double
    /// `percent` (cash back) or `per-dollar` (points or miles).
    var unit: String
    var capAmount: Double?
    /// `month`, `quarter`, `year` or `cycle`.
    var capPeriod: String?
    var capUnknown: Bool
    /// What it needs beyond the purchase: `activation`, `issuer-booking`, `preferred-rewards-tier`.
    var requires: [String]
    /// A way of paying it is limited to, such as Apple Pay.
    var paysWith: String?
    /// The first and last days it applies, as `yyyy-MM-dd`.
    var validFrom: String?
    var validTo: String?
    /// It applies only for the first this many months after the account is opened.
    var firstMonths: Int?
    /// The Preferred Rewards tier it is for.
    var tier: String?
    /// What only the cardholder can answer for it to apply, such as when the account was opened.
    var needs: [String]
    var conditions: [String]
    /// The merchants it is limited to.
    var merchants: [String]
    var evidence: Evidence

    /// The issuer's sentence that states the rule, word for word, and the page it is on.
    nonisolated struct Evidence: Codable, Hashable, Sendable {
        var quote: String
        var url: String
    }
}
