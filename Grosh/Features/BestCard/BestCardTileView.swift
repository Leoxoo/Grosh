import SwiftUI

/// One Reward category's tile on Best Card: the Card it shows (its image, or its symbol), the Reward category, the
/// Effective rate in a green capsule, and what the rate Needs. A star marks the user's Go-to card, and an orange mark
/// says another Card earns more and Needs nothing more. A Reward category no Card earns on shows 0%.
struct BestCardTileView: View {
    let tile: BestCardTile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                mark
                Spacer(minLength: 0)
                if tile.isBeaten {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                } else if tile.isGoTo {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .frame(height: 36, alignment: .top)
            Text(tile.reward.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            EffectiveRateBadge(rate: CardRateText.percent(tile.shown?.earning.effectiveRate ?? 0))
                .font(.subheadline)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var mark: some View {
        if let card = tile.shown?.card {
            CardMark(card: card, height: 36)
        } else {
            CardMark(image: nil, color: .secondary, height: 36)
        }
    }

    /// The line under the rate: what it Needs, else the Card's name, or "No Card".
    private var caption: String {
        guard let shown = tile.shown else { return String(localized: Strings.BestCard.noCard) }
        let needs = shown.earning.needs.map(CardRateText.need)
        return needs.isEmpty ? shown.card.name : needs.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        var parts = [tile.reward.name]
        if let shown = tile.shown {
            parts.append(shown.card.name)
            parts.append(CardRateText.percent(shown.earning.effectiveRate))
            parts += shown.earning.needs.map(CardRateText.need)
        } else {
            parts.append(String(localized: Strings.BestCard.noCard))
            parts.append(CardRateText.percent(0))
        }
        if tile.isGoTo { parts.append(String(localized: Strings.BestCard.goTo)) }
        if tile.isBeaten { parts.append(String(localized: Strings.BestCard.earnsMore)) }
        return parts.joined(separator: ", ")
    }
}
