import SwiftUI

/// What opens from a Best Card tile: every unarchived Card's rate on the Reward category, and the rates limited to
/// stores, best first, each with what it Needs. When the tile carries the orange mark, a section of its own says what
/// it means: which Card earns more than the Go-to card, and by how much. It sits under the rows, so that it coming and
/// going as a swipe changes the Go-to card moves no row mid-swipe. Tapping a Card opens its page; swiping it makes
/// it the Go-to card for the Reward category, or stops it being one.
struct BestCardRewardView: View {
    let reward: RewardCategory

    @CurrentBestCard private var bestCard
    @Environment(\.displayScale) private var displayScale
    @State private var errorMessage: String?

    var body: some View {
        let (tile, rows) = bestCard.detail(for: reward)
        List {
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        NavigationLink {
                            CardTransactionsView(card: row.card)
                        } label: {
                            label(row)
                        }
                        .swipeActions(edge: .leading) { goToButton(row) }
                        .contextMenu { goToButton(row) }
                    }
                } footer: {
                    Text(Strings.BestCard.rowsFooter(reward.name))
                }
            }
            if let goTo = tile.shown, let beatenBy = tile.beatenBy {
                Section {
                    Label {
                        Text(Strings.BestCard.earnsMoreExplanation(
                            beatenBy.card.displayName, CardRateText.percent(beatenBy.earning.effectiveRate),
                            goTo.card.displayName, CardRateText.percent(goTo.earning.effectiveRate)
                        ))
                        .font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(Strings.BestCard.noRates(reward.name), systemImage: reward.symbolName)
                } description: {
                    Text(Strings.BestCard.noRatesMessage)
                }
            }
        }
        .navigationTitle(reward.name)
        .errorAlert(Strings.BestCard.couldntChange, message: $errorMessage)
    }

    private func label(_ row: BestCardRow) -> some View {
        HStack(spacing: 12) {
            CardMark(card: row.card, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.card.displayName)
                    if row.isGoTo {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(Text(Strings.BestCard.goTo))
                    }
                }
                if !row.needs.isEmpty {
                    Text(row.needs.map(CardRateText.need).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            EffectiveRateBadge(rate: CardRateText.percent(row.effectiveRate))
        }
    }

    @ViewBuilder private func goToButton(_ row: BestCardRow) -> some View {
        if row.isGoTo {
            Button(Strings.BestCard.removeGoTo, systemImage: "star.slash") {
                Log.store.perform("Changing a Go-to card", errorMessage: &errorMessage) {
                    try row.card.removeGoTo(for: reward.id)
                }
            }
        } else {
            Button(Strings.BestCard.makeGoTo, systemImage: "star") {
                Log.store.perform("Changing a Go-to card", errorMessage: &errorMessage) {
                    try row.card.makeGoTo(for: reward.id)
                }
            }
            .tint(.yellow)
        }
    }
}
