import SwiftUI

/// What opens from a Best Card tile: every unarchived Card's rate on the Reward category, and the rates limited to
/// stores, best first, each with what it Needs. Tapping a Card opens its page; swiping it makes it the Go-to card for
/// the Reward category, or stops it being one.
struct BestCardRewardView: View {
    let reward: RewardCategory

    @CurrentBestCard private var bestCard
    @Environment(\.displayScale) private var displayScale
    @State private var errorMessage: String?

    var body: some View {
        let rows = bestCard.rows(for: reward)
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
            CardMark(card: row.card, height: 28, symbolFont: .title3)
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
