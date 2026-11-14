import SwiftUI

/// The top of a Card's page: what the Card earns, one row per Reward category, best first and Everything else last.
/// A points or miles Card shows each rate's Multiplier as a pill. A row opens its details. A Card that isn't linked
/// offers Add rewards, which links it to the catalog.
struct CardRewardsSection: View {
    let card: Card

    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.today) private var today
    @State private var isLinking = false
    @State private var errorMessage: String?

    var body: some View {
        let rewards = CardRewards(of: card, in: catalog)
        let rates = rewards.rates(on: today)
        Section {
            if rewards.entry == nil {
                Button {
                    isLinking = true
                } label: {
                    HStack {
                        Text(Strings.Rewards.addRewards)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }
            if let entry = rewards.entry, rates.isEmpty || rewards.isNoLongerInCatalog {
                CatalogCardLabel(card: entry, isNoLongerInCatalog: rewards.isNoLongerInCatalog)
            }
            ForEach(rates) { rate in
                NavigationLink {
                    CardRateDetailView(rate: rate, entry: rewards.entry, pointValueCents: rewards.pointValueCents)
                } label: {
                    CardRateRow(rate: rate)
                }
            }
        } header: {
            Text(Strings.Rewards.rewards)
        } footer: {
            if rewards.isNoLongerInCatalog {
                Text(Strings.Rewards.noLongerInCatalogFooter)
            }
        }
        .sheet(isPresented: $isLinking) {
            CatalogCardSearchSheet { entry in
                Log.store.perform("Linking a Card to the rewards catalog", errorMessage: &errorMessage) {
                    try card.link(to: entry)
                }
            }
        }
        .errorAlert(Strings.Cards.couldntChange, message: $errorMessage)
    }
}

/// One rate: the Multiplier pill for a points or miles Card, the Reward category, and the Effective rate on the right.
private struct CardRateRow: View {
    let rate: CardRate

    var body: some View {
        HStack(spacing: 8) {
            if let multiplier = rate.multiplier {
                Text(Strings.Rewards.multiplier(CardRateText.number(multiplier)))
                    .monospacedDigit()
                    .capsuleBadge(.tint, on: .accentColor)
            }
            Text(rate.reward.name)
            Spacer()
            Text(CardRateText.percent(rate.effectiveRate))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One rate's details: what it is worth, its cap, what it needs, its dates, the bank's conditions, the bank's own
/// sentence and the page it is on.
struct CardRateDetailView: View {
    let rate: CardRate
    let entry: CatalogCard?
    let pointValueCents: Double

    var body: some View {
        let rule = rate.rule
        List {
            Section {
                LabeledContent(Strings.Rewards.effectiveRate) {
                    Text(CardRateText.percent(rate.effectiveRate))
                        .monospacedDigit()
                }
                if let multiplier = rate.multiplier {
                    Text(Strings.Rewards.pointsWorth(CardRateText.number(multiplier), CardRateText.number(pointValueCents)))
                        .foregroundStyle(.secondary)
                }
                if let cap = capText(rule) {
                    LabeledContent(Strings.Rewards.cap, value: cap)
                }
                if let dates = datesText(rule) {
                    LabeledContent(Strings.Rewards.dates, value: dates)
                }
                if rule.requires.contains("activation") {
                    Label(Strings.Rewards.needsActivation, systemImage: "bolt.badge.checkmark")
                }
                if rule.requires.contains("issuer-booking") {
                    Label(Strings.Rewards.bookThroughIssuer, systemImage: "building.columns")
                }
            }

            let conditions = rule.conditions + (entry?.cardConditions ?? [])
            if !conditions.isEmpty {
                Section(Strings.Rewards.conditions) {
                    ForEach(conditions, id: \.self) { condition in
                        Text(condition)
                    }
                }
            }

            Section(Strings.Rewards.fromTheBank) {
                Text(verbatim: "“\(rule.evidence.quote)”")
                    .italic()
                    .textSelection(.enabled)
                if let url = URL(string: rule.evidence.url) {
                    Link(destination: url) {
                        Label(Strings.Rewards.source, systemImage: "safari")
                    }
                }
            }
        }
        .navigationTitle(rate.reward.name)
    }

    private func capText(_ rule: CatalogRule) -> String? {
        guard let amount = rule.capAmount.map(CardRateText.dollars) else {
            return rule.capUnknown ? String(localized: Strings.Rewards.capUnknown) : nil
        }
        return switch rule.capPeriod {
        case "month": String(localized: Strings.Rewards.capPerMonth(amount))
        case "quarter": String(localized: Strings.Rewards.capPerQuarter(amount))
        case "year": String(localized: Strings.Rewards.capPerYear(amount))
        case "cycle": String(localized: Strings.Rewards.capPerStatement(amount))
        default: String(localized: Strings.Rewards.capTotal(amount))
        }
    }

    private func datesText(_ rule: CatalogRule) -> String? {
        switch (rule.validFrom.map(CardRateText.day), rule.validTo.map(CardRateText.day)) {
        case let (from?, to?): String(localized: Strings.Rewards.datesBetween(from, to))
        case let (from?, nil): String(localized: Strings.Rewards.datesFrom(from))
        case let (nil, to?): String(localized: Strings.Rewards.datesUntil(to))
        case (nil, nil): nil
        }
    }
}
