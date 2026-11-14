import Foundation
@testable import Grosh

/// A small rewards catalog, written as `tools/rewards-catalog/pipeline/publish.py` writes `rewards-catalog.json`
/// (`formatVersion` 1, every key present, `null` when unused), standing in for the real one until its rules are reviewed.
///
/// - `test-savory-cash`: cash back, 3% Dining and Groceries, 1% Everything else, plus rules this ticket doesn't show
///   (rotating, Apple Pay, merchants, a Preferred Rewards tier boost, one that needs the account's open date).
/// - `test-voyager-points`: points, 3× Dining, 2× Travel, 1× Everything else, and a 5× Hotels rule that ended.
/// - `test-old-miles`: miles, 2× Everything else.
enum RewardsCatalogFixture {
    static func rule(
        _ categories: [String], _ rate: Double, unit: String = "percent", selection: String = "fixed",
        capAmount: Double? = nil, capPeriod: String? = nil, requires: [String] = [], paysWith: String? = nil,
        validFrom: String? = nil, validTo: String? = nil, firstMonths: Int? = nil, tier: String? = nil,
        needs: [String] = [], conditions: [String] = [], merchants: [String] = [], quote: String = "A quote."
    ) -> [String: Any?] {
        [
            "categories": categories, "selection": selection, "picks": nil, "hasOtherChoices": false, "rate": rate,
            "unit": unit, "capAmount": capAmount, "capPeriod": capPeriod, "capUnknown": false, "requires": requires,
            "paysWith": paysWith, "validFrom": validFrom, "validTo": validTo, "firstMonths": firstMonths, "tier": tier,
            "needs": needs, "conditions": conditions, "merchants": merchants,
            "evidence": ["quote": quote, "url": "https://bank.test/card"],
        ]
    }

    static func card(
        _ id: String, _ name: String, issuer: String, kind: String, network: String? = "Visa", annualFee: Double = 0,
        rules: [[String: Any?]]
    ) -> [String: Any?] {
        [
            "id": id, "name": name, "issuer": issuer, "network": network, "isBusiness": false, "annualFee": annualFee,
            "rewardKind": kind, "rewardProgram": kind == "cashback" ? nil : "TEST_POINTS", "baseEarnRate": 1,
            "discontinued": false, "sourceUrl": "https://bank.test/card", "verifiedAt": "2026-11-01",
            "cardConditions": [], "bonusesStack": false, "rules": rules,
        ]
    }

    static var savoryRules: [[String: Any?]] { [
        rule(["dining", "groceries"], 3, capAmount: 2500, capPeriod: "quarter", conditions: ["Not at superstores."],
             quote: "Earn 3% cash back on dining and at grocery stores."),
        rule(["everything-else"], 1, quote: "Earn 1% on all other purchases."),
        rule(["gas"], 5, selection: "rotating", requires: ["activation"]),
        rule(["everything-else"], 2, paysWith: "Apple Pay"),
        rule(["online-shopping"], 5, merchants: ["Amazon"]),
        rule(["dining"], 5.25, requires: ["preferred-rewards-tier"], tier: "platinum"),
        rule(["groceries"], 6, firstMonths: 12, needs: ["account-opened"]),
    ] }

    static var savory: [String: Any?] {
        card("test-savory-cash", "Savory Cash", issuer: "Test Bank", kind: "cashback", network: "Mastercard", rules: savoryRules)
    }

    static var voyager: [String: Any?] { card("test-voyager-points", "Voyager Points", issuer: "Example Credit Union", kind: "points",
                              annualFee: 95, rules: [
        rule(["everything-else"], 1, unit: "per-dollar"),
        rule(["dining"], 3, unit: "per-dollar", requires: ["activation"]),
        rule(["travel"], 2, unit: "per-dollar"),
        rule(["hotels"], 5, unit: "per-dollar", validFrom: "2026-01-01", validTo: "2026-06-30"),
    ]) }

    static var oldMiles: [String: Any?] { card("test-old-miles", "Old Miles", issuer: "Test Bank", kind: "miles", rules: [
        rule(["everything-else"], 2, unit: "per-dollar"),
    ]) }

    /// The catalog's file, with `cards` in it.
    static func data(formatVersion: Int = 1, cards: [[String: Any?]] = [savory, voyager, oldMiles], extra: [String: Any] = [:]) throws -> Data {
        var document: [String: Any] = ["formatVersion": formatVersion, "publishedAt": "2026-11-02", "cards": cards.map(jsonObject)]
        document.merge(extra) { _, new in new }
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    static func catalog(cards: [[String: Any?]] = [savory, voyager, oldMiles]) throws -> RewardsCatalog {
        try RewardsCatalog(data: data(cards: cards))
    }

    /// `value` with each `nil` written as JSON's `null`.
    private static func jsonObject(_ value: [String: Any?]) -> [String: Any] {
        value.mapValues { field -> Any in
            switch field {
            case .none: NSNull()
            case .some(let rules as [[String: Any?]]): rules.map(jsonObject)
            case .some(let nested as [String: Any?]): jsonObject(nested)
            case .some(let other): other
            }
        }
    }
}
