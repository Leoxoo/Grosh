import SwiftData
import SwiftUI

/// A category's Rewards as, as a row: the category, or "Rewards as" in its editor, then what it counts as and a chevron
/// to the list that changes it.
struct RewardsAsSummary<Label: View>: View {
    let own: [String]
    let parent: Category?
    let rewards: [RewardCategory]
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack {
            label()
                .layoutPriority(1)
            Spacer()
            Text(RewardsAsList.summary(own: own, parent: parent, rewards: rewards))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The Reward categories a category can count as, each with its icon and a checkmark on each it does, so it can count
/// as several (ADR-0015). A subcategory's first choice is to follow its parent; Everything else is last, and never
/// checked beside another. Each tap sets the new choices at once.
struct RewardsAsList: View {
    let categoryName: String
    let parent: Category?
    let rewards: [RewardCategory]
    @Binding var own: [String]

    var body: some View {
        let checked = RewardCategory.shownChoices(own: own, isSubcategory: parent != nil)
        List {
            Section {
                if let parent {
                    row(checked: own.isEmpty) {
                        CategoryIcon(category: parent)
                        Text(Self.sameAsParent(parent, rewards: rewards))
                    } tap: {
                        own = []
                    }
                }
                ForEach(rewards) { reward in
                    row(checked: checked.contains(reward.id)) {
                        SymbolCircle(symbolName: reward.symbolName, color: reward.color)
                        Text(reward.name)
                    } tap: {
                        own = RewardCategory.toggled(reward.id, in: checked, listed: rewards)
                    }
                }
            } header: {
                Text(Strings.Rewards.rewardsAs)
            } footer: {
                Text(Strings.Rewards.rewardsAsFooter)
            }
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(
        checked: Bool, @ViewBuilder content: () -> some View, tap: @escaping () -> Void
    ) -> some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                content()
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    /// What a row of Rewards as shows: following the parent, or the checked Reward categories' names.
    static func summary(own: [String], parent: Category?, rewards: [RewardCategory]) -> String {
        if let parent, own.isEmpty { return String(localized: sameAsParent(parent, rewards: rewards)) }
        return RewardCategory.names(of: RewardCategory.shownChoices(own: own, isSubcategory: parent != nil), in: rewards)
    }

    private static func sameAsParent(_ parent: Category, rewards: [RewardCategory]) -> LocalizedStringResource {
        Strings.Categories.sameAsParent(parent.name, RewardCategory.names(of: parent.rewardsAs ?? [], in: rewards))
    }
}
