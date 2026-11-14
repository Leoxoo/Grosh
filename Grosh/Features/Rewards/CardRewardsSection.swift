import SwiftData
import SwiftUI

/// The top of a Card's page: what a purchase in each Reward category earns with the Card, every bonus that covers it
/// counted and added up when the card's Bonuses add up, best first and Everything else last; its rates on Your choice or
/// the top category; and the rates it earns only when paid a certain way or at certain merchants. Then the current
/// rotating quarter, its dates and days left first, and the next one. A points or miles Card shows each rate's
/// Multiplier as a pill, and an Edited rate says so. A row opens its details. A Card that isn't linked offers Add
/// rewards, which links it to the catalog; the pencil opens the rate editor.
struct CardRewardsSection: View {
    let card: Card
    let today: CalendarDay

    @Environment(\.rewardsCatalog) private var catalog
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]
    @State private var isLinking = false
    @State private var isEditingRates = false
    @State private var errorMessage: String?

    var body: some View {
        let rewards = CardRewards(of: card, in: catalog)
        let own = ownRewardCategories.map(RewardCategory.init)
        let page = rewards.page(on: today, own: own)
        let currencyCode = card.payingWallet.currencyCodeOrDefault
        Group {
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
                if let entry = rewards.entry, page.earned.isEmpty || rewards.isNoLongerInCatalog {
                    CatalogCardLabel(card: entry, isNoLongerInCatalog: rewards.isNoLongerInCatalog)
                }
                ForEach(page.earned) { earning in
                    NavigationLink {
                        EarnedRateDetailView(earning: earning, rewards: rewards, currencyCode: currencyCode)
                    } label: {
                        EarnedRateRow(earning: earning)
                    }
                }
                ForEach(page.choices) { choice in
                    if choice.isTopSpend && choice.chosen.isEmpty {
                        // Only a top-spend rate with no Your choice reads the Card's spending this period.
                        TopSpendRow(card: card, choiceKey: choice.key, today: today, own: own)
                    } else {
                        NavigationLink {
                            YourChoiceView(card: card, choice: choice)
                        } label: {
                            ChoiceRow(choice: choice)
                        }
                    }
                }
                if let rotating = page.rotatingWithoutQuarter {
                    ConditionalRow(text: Strings.Rewards.onRotatingCategories(CardRateText.percent(rotating.effectiveRate)))
                }
                ForEach(Array(page.conditional.enumerated()), id: \.offset) { _, rate in
                    NavigationLink {
                        CardRateDetailView(rate: rate, rewards: rewards, currencyCode: currencyCode)
                    } label: {
                        ConditionalRow(text: CardRateText.condition(of: rate))
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

            ForEach(page.quarters) { quarter in
                QuarterSection(quarter: quarter, today: today)
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

/// What a purchase in one Reward category earns: the Multiplier pill for a points or miles Card, the category, Edited
/// when the user changed a rate in it, the Effective rate on the right, and how it adds up under it ("1% base + 2% +
/// 4% Oct–Dec") or which quarter it is.
private struct EarnedRateRow: View {
    let earning: PurchaseEarning

    var body: some View {
        HStack(spacing: 8) {
            if let multiplier = earning.multiplier {
                Text(Strings.Rewards.multiplier(CardRateText.number(multiplier)))
                    .monospacedDigit()
                    .capsuleBadge(.tint, on: .accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(earning.reward.name)
                    if earning.isEdited {
                        Text(Strings.Rewards.edited)
                            .capsuleBadge(.secondary, on: .secondary)
                    }
                }
                if let detail = CardRateText.breakdown(of: earning) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(CardRateText.percent(earning.effectiveRate))
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a purchase in one Reward category earns, how it adds up, and each rate it is made of, which opens its details.
private struct EarnedRateDetailView: View {
    let earning: PurchaseEarning
    let rewards: CardRewards
    let currencyCode: String

    var body: some View {
        List {
            Section {
                LabeledContent(Strings.Rewards.effectiveRate) {
                    Text(CardRateText.percent(earning.effectiveRate))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            } footer: {
                if earning.isAddedUp {
                    Text(Strings.Rewards.addsUpFooter)
                }
            }
            Section(earning.isAddedUp ? Strings.Rewards.howItAddsUp : Strings.Rewards.rate) {
                ForEach(Array(earning.parts.enumerated()), id: \.offset) { index, part in
                    NavigationLink {
                        CardRateDetailView(rate: part.rate, rewards: rewards, currencyCode: currencyCode)
                    } label: {
                        LabeledContent(CardRateText.partName(part, isFirst: index == 0, of: earning)) {
                            Text(index == 0 || !earning.isAddedUp
                                ? CardRateText.percent(part.adds) : "+" + CardRateText.percent(part.adds))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(earning.reward.name)
    }
}

/// A rotating quarter in a section of its own: its dates in the accent color and the days left, or when it starts, its
/// rate, each Reward category and merchant it covers, and its spending limit.
private struct QuarterSection: View {
    let quarter: QuarterRate
    let today: CalendarDay

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CardRateText.dayRange(from: quarter.from, to: quarter.to))
                        .font(.headline)
                        .foregroundStyle(quarter.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(quarter.isCurrent
                        ? Strings.Rewards.daysLeft(quarter.daysLeft(from: today))
                        : Strings.Rewards.datesFrom(CardRateText.day(quarter.from)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(CardRateText.percent(quarter.rate.effectiveRate))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            ForEach(quarter.rewards) { reward in
                Label(reward.name, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(quarter.isCurrent ? .primary : .secondary)
            }
            ForEach(quarter.merchants, id: \.self) { merchant in
                Label(merchant, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            if let cap = quarter.rate.cap.flatMap({ CardRateText.cap(amountOf: $0, currencyCode: $0.currencyCode ?? "USD") }) {
                LabeledContent(Strings.Rewards.spendingLimit, value: cap)
            }
        } header: {
            Text(quarter.isCurrent ? Strings.Rewards.quarterlyBonus : Strings.Rewards.nextQuarter)
        } footer: {
            if quarter.needsActivation {
                Text(Strings.Rewards.activateWithBank)
            }
        }
    }
}

/// A rate on Your choice or on the top category: "3% · Your choice: Not set", "3% · Gas (Your choice)" or "5% on your
/// top category (Dining so far)".
private struct ChoiceRow: View {
    let choice: ChoiceRate

    var body: some View {
        let rate = CardRateText.percent(choice.rate.effectiveRate)
        HStack {
            if !choice.chosen.isEmpty {
                Text(Strings.Rewards.yourChoiceIs(rate, choice.chosen.map(\.name).formatted(.list(type: .and))))
            } else if choice.isTopSpend {
                if let top = choice.topSpend {
                    Text(Strings.Rewards.topCategory(rate, top.name))
                } else {
                    Text(Strings.Rewards.topCategoryNone(rate))
                }
            } else {
                Text(Strings.Rewards.yourChoiceNotSet(rate))
            }
            Spacer()
        }
    }
}

/// A rate shown and never earned: on rotating categories with no quarter dated yet, or paid a certain way or at certain
/// merchants, which Grosh doesn't record.
private struct ConditionalRow: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}

/// A top-spend rate with no Your choice: "5% on your top category (Dining so far)", the category worked out from the
/// Card's spending this period, which it reads with one query narrowed to the Card and the period (``CardTopSpend``).
private struct TopSpendRow: View {
    let card: Card
    let choiceKey: String
    let own: [RewardCategory]
    let today: CalendarDay

    @Environment(\.rewardsCatalog) private var catalog
    @Query private var paidThisPeriod: [Transaction]

    init(card: Card, choiceKey: String, today: CalendarDay, own: [RewardCategory]) {
        self.card = card
        self.choiceKey = choiceKey
        self.today = today
        self.own = own
        _paidThisPeriod = Query(CardTopSpend.read(of: card, on: today))
    }

    var body: some View {
        let spending = CardTopSpend.spending(of: paidThisPeriod, in: card.period(containing: today))
        let choice = CardRewards(of: card, in: catalog).page(on: today, own: own, spending: spending).choices
            .first { $0.key == choiceKey }
        if let choice {
            NavigationLink {
                YourChoiceView(card: card, choice: choice)
            } label: {
                ChoiceRow(choice: choice)
            }
        }
    }
}

/// Picks Your choice for a rate whose Reward category the cardholder chooses, or in place of the top category.
private struct YourChoiceView: View {
    let card: Card
    let choice: ChoiceRate

    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if choice.isTopSpend {
                    row(String(localized: Strings.Rewards.topCategoryAutomatic), isChosen: choice.chosen.isEmpty) { set([]) }
                }
                ForEach(choice.options) { option in
                    row(option.name, isChosen: choice.chosen.contains(option)) { set(choice.choosing(option)) }
                }
            } footer: {
                Text(choice.isTopSpend ? Strings.Rewards.topCategoryFooter : Strings.Rewards.yourChoiceFooter(choice.picks))
            }
            if let cap = choice.rate.cap.flatMap({ CardRateText.cap($0, currencyCode: $0.currencyCode ?? "USD") }) {
                Section {
                    LabeledContent(Strings.Rewards.cap, value: cap)
                }
            }
        }
        .navigationTitle(Strings.Rewards.yourChoice)
        .errorAlert(Strings.Cards.couldntChange, message: $errorMessage)
    }

    private func row(_ title: String, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func set(_ rewards: [String]) {
        let saved = Log.store.perform("Setting Your choice", errorMessage: &errorMessage) {
            try card.setYourChoice(rewards, for: choice.key, in: catalog)
        }
        if saved && choice.picks == 1 {
            dismiss()
        }
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
