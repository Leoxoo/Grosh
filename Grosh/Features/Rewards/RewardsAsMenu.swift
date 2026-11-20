import SwiftUI

/// A menu of the Reward categories a category can count as, with a checkmark on each it does, so it can count as
/// several (ADR-0015). A subcategory's first choice is to follow its parent. The menu stays open while the checkmarks
/// change, and the row shows what is checked.
struct RewardsAsMenu<Label: View>: View {
    /// The category's own Rewards as: none to follow its parent's, or for a top-level one, Everything else.
    let own: [String]
    /// The category's parent, for a subcategory.
    let parent: Category?
    /// Every Reward category, in list order.
    let rewards: [RewardCategory]
    let set: ([String]) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        let checked = RewardCategory.shownChoices(own: own, isSubcategory: parent != nil)
        Menu {
            if let parent {
                Toggle(isOn: Binding(get: { own.isEmpty }, set: { if $0 { set([]) } })) {
                    Text(sameAsParent(parent))
                }
            }
            ForEach(rewards) { reward in
                Toggle(reward.name, isOn: Binding(
                    get: { checked.contains(reward.id) },
                    set: { _ in set(RewardCategory.toggled(reward.id, in: checked, listed: rewards)) }
                ))
            }
        } label: {
            HStack {
                label()
                    .layoutPriority(1)
                Spacer()
                summary(checked)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .menuActionDismissBehavior(.disabled)
        // A menu's label takes the accent color; the category's name stays in the text color, as a picker row's did.
        .tint(.primary)
    }

    /// What the row shows as checked: following the parent, or the checked Reward categories' names.
    private func summary(_ checked: [String]) -> Text {
        if let parent, own.isEmpty { return Text(sameAsParent(parent)) }
        return Text(RewardCategory.names(of: checked, in: rewards))
    }

    private func sameAsParent(_ parent: Category) -> LocalizedStringResource {
        Strings.Categories.sameAsParent(parent.name, RewardCategory.names(of: parent.rewardsAs ?? [], in: rewards))
    }
}
