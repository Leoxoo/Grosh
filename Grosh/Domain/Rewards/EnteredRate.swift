import Foundation
import SwiftData

/// How often a rate's cap starts again.
nonisolated enum RateCapPeriod: String, Codable, CaseIterable, Sendable {
    case month, quarter, year
    /// Each statement period, which the catalog calls a billing cycle.
    case statement

    /// The period a catalog rule's `capPeriod` names, or `nil` for none or one the app doesn't know.
    init?(catalog name: String?) {
        switch name {
        case "cycle": self = .statement
        case let name?: self.init(rawValue: name)
        case nil: return nil
        }
    }
}

/// How much of a rate's spending earns it: up to an amount each period, or capped by an amount the bank doesn't give.
/// Shown with the rate; nothing tracks spend toward it.
nonisolated struct RateCap: Hashable, Sendable {
    var amount: Double?
    /// `nil` for a cap over the rate's whole life.
    var period: RateCapPeriod?
    var isUnknown = false
    /// The currency of ``amount``: US dollars for the catalog's caps, `nil` for one the user entered, which is in the
    /// Card's paying wallet's currency.
    var currencyCode: String?
}

/// A rate the user entered on a Card: a Custom card's own, or on a linked Card an Edited rate, which takes the
/// catalog's place for that Reward category on that Card alone (ADR-0014). A Card has at most one per Reward category.
nonisolated struct EnteredRate: Codable, Hashable, Identifiable, Sendable {
    /// The Reward category it earns on (``RewardCategory/id``), the user's own included.
    var reward: String
    /// Percent for a cash back Card, points or miles per dollar for one that earns points. `nil` on a linked Card
    /// removes the catalog's rate for ``reward``.
    var rate: Double?
    /// The most spending that earns it each ``capPeriod``, in the Card's currency.
    var capAmount: Double?
    var capPeriod: RateCapPeriod?
    /// The first and last days it earns, as ``CalendarDay/rawValue``s.
    var validFrom: Int?
    var validTo: Int?

    init(reward: String, rate: Double?) {
        self.reward = reward
        self.rate = rate
    }

    var id: String { reward }

    /// The rate the editor starts from to change the Card's rate for `row`: what the user entered, else the catalog's
    /// with its cap and dates, stated in the Card's unit at the same Effective rate (a percent rule on a points Card is
    /// that percent in points at the Card's Point value).
    init(editing row: EditableRate, earnsPoints: Bool, pointValueCents: Double) {
        if let entered = row.entered, !entered.isRemoval {
            self = entered
            return
        }
        self.init(reward: row.reward.id, rate: nil)
        guard let catalog = row.catalog else { return }
        rate = earnsPoints ? catalog.effectiveRate / pointValueCents : catalog.effectiveRate
        capAmount = catalog.cap?.amount
        capPeriod = catalog.cap?.period
        from = catalog.validFrom
        to = catalog.validTo
    }

    /// Whether it removes the catalog's rate rather than giving one.
    var isRemoval: Bool { rate == nil }

    /// The first day it earns, if it has one.
    var from: CalendarDay? {
        get { validFrom.map(CalendarDay.init(rawValue:)) }
        set { validFrom = newValue?.rawValue }
    }

    /// The last day it earns, if it has one.
    var to: CalendarDay? {
        get { validTo.map(CalendarDay.init(rawValue:)) }
        set { validTo = newValue?.rawValue }
    }

    /// Its cap, in the Card's currency, if it has one.
    var cap: RateCap? {
        capAmount.map { RateCap(amount: $0, period: capPeriod) }
    }

    /// Whether it earns on `today`: between its dates, where it has them.
    func applies(on today: CalendarDay) -> Bool {
        !(from.map { today < $0 } ?? false) && !(to.map { $0 < today } ?? false)
    }
}

/// Why a rate the user entered was refused.
nonisolated enum EnteredRateError: RuleRefusal, Equatable {
    /// A rate is a number above zero.
    case rateOutOfRange
    /// A cap is an amount above zero.
    case capOutOfRange
    /// The first day comes before the last.
    case datesOutOfOrder
    /// A Card has one rate per Reward category.
    case categoryTaken
}

extension EnteredRateError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rateOutOfRange: String(localized: Strings.Rewards.rateOutOfRange)
        case .capOutOfRange: String(localized: Strings.Rewards.capOutOfRange)
        case .datesOutOfOrder: String(localized: Strings.Rewards.datesOutOfOrder)
        case .categoryTaken: String(localized: Strings.Rewards.categoryTaken)
        }
    }
}

nonisolated extension EnteredRate {
    /// Checks the rate as the editor saves it: a rate above zero, any cap above zero, and dates in order.
    func validate() throws {
        guard let rate, rate.isFinite, rate > 0 else { throw EnteredRateError.rateOutOfRange }
        if let capAmount {
            guard capAmount.isFinite, capAmount > 0 else { throw EnteredRateError.capOutOfRange }
        }
        if let from, let to {
            guard from <= to else { throw EnteredRateError.datesOutOfOrder }
        }
    }
}

extension Card {
    /// The rates the user entered on this Card: a Custom card's, or a linked Card's Edited rates and removals
    /// (ADR-0014). Decoded on each read, so a screen reads it once per Card per draw, through ``CardRewards``.
    var enteredRates: [EnteredRate] {
        guard let enteredRatesData else { return [] }
        return Log.store.attempt("Reading a Card's entered rates") {
            try JSONDecoder().decode([EnteredRate].self, from: enteredRatesData)
        } ?? []
    }

    /// Keeps `rates` as the Card's entered rates, without saving.
    func keepEnteredRates(_ rates: [EnteredRate]) throws {
        let kept = rates.sorted { $0.reward < $1.reward }
        if kept.isEmpty {
            enteredRatesData = nil
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        enteredRatesData = try encoder.encode(kept)
    }

    /// Adds `rate`, or saves it in place of the one for `oldReward` (the category it had before the user changed it).
    /// On a linked Card it is an Edited rate, and moving a rate to another category removes the catalog's rate for the
    /// old one, if its entry in `catalog` has one, so it doesn't come back. Saves.
    @MainActor
    func saveRate(in catalog: RewardsCatalog, _ rate: EnteredRate, replacing oldReward: String?) throws {
        try rate.validate()
        var rates = enteredRates.filter { $0.reward != oldReward }
        if rates.contains(where: { $0.reward == rate.reward && !$0.isRemoval }) {
            throw EnteredRateError.categoryTaken
        }
        rates.removeAll { $0.reward == rate.reward }
        if let oldReward, oldReward != rate.reward, CardRewards(of: self, in: catalog).catalogCovers(oldReward) {
            rates.append(EnteredRate(reward: oldReward, rate: nil))
        }
        try keepEnteredRates(rates + [rate])
        try saveToStore()
    }

    /// Removes the Card's rate for `reward`. On a linked Card whose entry in `catalog` has a rate for it, the removal is
    /// kept as an Edited rate, so the catalog's doesn't come back; otherwise the entered rate just goes. Saves.
    @MainActor
    func removeRate(for reward: String, in catalog: RewardsCatalog) throws {
        var rates = enteredRates.filter { $0.reward != reward }
        if CardRewards(of: self, in: catalog).catalogCovers(reward) {
            rates.append(EnteredRate(reward: reward, rate: nil))
        }
        try keepEnteredRates(rates)
        try saveToStore()
    }

    /// Takes the Edited rate for `reward` away, so the Card follows the catalog's again. Saves.
    func resetRate(for reward: String) throws {
        try keepEnteredRates(enteredRates.filter { $0.reward != reward })
        try saveToStore()
    }

    /// Sets whether a Custom card earns cash back or points; a linked Card earns what its entry does. Saves.
    func setRewardKind(_ kind: RewardKind) throws {
        ownRewardKindRaw = kind.rawValue
        try saveToStore()
    }

    /// What the user set the Card to earn, for a Custom card.
    var ownRewardKind: RewardKind? {
        ownRewardKindRaw.flatMap(RewardKind.init(rawValue:))
    }
}
