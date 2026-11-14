import SwiftData
import SwiftUI

/// The top of a Card's page: what the Card earns, one row per Reward category, best first and Everything else last.
/// A points or miles Card shows each rate's Multiplier as a pill, and an Edited rate says so. A row opens its details.
/// A Card that isn't linked offers Add rewards, which links it to the catalog; the pencil opens the rate editor.
struct CardRewardsSection: View {
    let card: Card

    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.today) private var today
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]
    @State private var isLinking = false
    @State private var isEditingRates = false
    @State private var errorMessage: String?

    var body: some View {
        let rewards = CardRewards(of: card, in: catalog)
        let rates = rewards.rates(on: today, own: ownRewardCategories.map(RewardCategory.init))
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
                    CardRateDetailView(rate: rate, rewards: rewards, currencyCode: card.payingWallet.currencyCodeOrDefault)
                } label: {
                    CardRateRow(rate: rate)
                }
            }
        } header: {
            HStack {
                Text(Strings.Rewards.rewards)
                Spacer()
                Button {
                    isEditingRates = true
                } label: {
                    Image(systemName: "pencil")
                        .accessibilityLabel(Strings.Rewards.editRates)
                }
            }
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
        .sheet(isPresented: $isEditingRates) {
            CardRatesEditor(card: card)
        }
        .errorAlert(Strings.Cards.couldntChange, message: $errorMessage)
    }
}

/// One rate: the Multiplier pill for a points or miles Card, the Reward category, and the Effective rate on the right.
struct CardRateRow: View {
    let rate: CardRate

    var body: some View {
        HStack(spacing: 8) {
            if let multiplier = rate.multiplier {
                Text(Strings.Rewards.multiplier(CardRateText.number(multiplier)))
                    .monospacedDigit()
                    .capsuleBadge(.tint, on: .accentColor)
            }
            Text(rate.reward.name)
            if rate.isEdited {
                Text(Strings.Rewards.edited)
                    .capsuleBadge(.secondary, on: .secondary)
            }
            Spacer()
            Text(CardRateText.percent(rate.effectiveRate))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One rate's details: what it is worth, its cap, its dates and what it needs, and for a catalog rate the bank's
/// conditions, its own sentence and the page it is on.
struct CardRateDetailView: View {
    let rate: CardRate
    let rewards: CardRewards
    /// The currency of a cap the user entered: the Card's paying wallet's.
    let currencyCode: String

    var body: some View {
        List {
            Section {
                LabeledContent(Strings.Rewards.effectiveRate) {
                    Text(CardRateText.percent(rate.effectiveRate))
                        .monospacedDigit()
                }
                if let multiplier = rate.multiplier {
                    Text(Strings.Rewards.pointsWorth(CardRateText.number(multiplier), CardRateText.number(rewards.pointValueCents)))
                        .foregroundStyle(.secondary)
                }
                if let cap = rate.cap.flatMap({ CardRateText.cap($0, currencyCode: $0.currencyCode ?? currencyCode) }) {
                    LabeledContent(Strings.Rewards.cap, value: cap)
                }
                if let dates = CardRateText.dates(from: rate.validFrom, to: rate.validTo) {
                    LabeledContent(Strings.Rewards.dates, value: dates)
                }
                if rate.rule?.requires.contains("activation") == true {
                    Label(Strings.Rewards.needsActivation, systemImage: "bolt.badge.checkmark")
                }
                if rate.rule?.requires.contains("issuer-booking") == true {
                    Label(Strings.Rewards.bookThroughIssuer, systemImage: "building.columns")
                }
            } footer: {
                if rate.isEdited {
                    Text(Strings.Rewards.editedFooter)
                }
            }

            if let rule = rate.rule {
                let conditions = rule.conditions + (rewards.entry?.cardConditions ?? [])
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
        }
        .navigationTitle(rate.reward.name)
    }
}
