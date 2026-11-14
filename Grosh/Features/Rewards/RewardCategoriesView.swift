import SwiftData
import SwiftUI

/// Account → Cards → Reward categories: each Reward category with the user's Expense categories that count as it.
/// Tapping a category changes what it counts as. The user adds Reward categories of their own here, and renames or
/// deletes them.
struct RewardCategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query private var allCategories: [Category]
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]
    @State private var errorMessage: String?
    @State private var naming: Naming?
    @State private var typedName = ""
    @State private var deleting: OwnRewardCategory?

    /// What the name alert is for: a new Reward category, or a new name for one of the user's own.
    private enum Naming: Identifiable {
        case add
        case rename(OwnRewardCategory)

        var id: String {
            switch self {
            case .add: "add"
            case .rename(let own): own.key
            }
        }
    }

    private var rewards: RewardCategories { RewardCategories(context: context) }

    var body: some View {
        let own = ownRewardCategories.map(RewardCategory.init)
        let listed = RewardCategory.listed(own: own)
        List {
            Section {
            } footer: {
                Text(Strings.Rewards.rewardCategoriesFooter)
            }
            ForEach(RewardCategories.map(of: allCategories, own: own)) { entry in
                Section {
                    if entry.categories.isEmpty {
                        Text(Strings.Rewards.noCategoriesCountAsIt)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entry.categories) { category in
                        RewardsAsRow(category: category, rewards: listed) { id in
                            Log.store.perform("Changing a category's Rewards as", errorMessage: &errorMessage) {
                                try rewards.setRewardsAs(of: category, to: id)
                            }
                        }
                    }
                } header: {
                    header(for: entry.reward)
                } footer: {
                    if entry.reward.isOwn {
                        Text(Strings.Rewards.ownRewardCategoryFooter)
                    }
                }
            }
        }
        .navigationTitle(Strings.Rewards.rewardCategories)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.Rewards.addRewardCategory, systemImage: "plus") {
                    typedName = ""
                    naming = .add
                }
            }
        }
        .alert(
            Text(naming.map { if case .rename = $0 { Strings.Rewards.renameRewardCategory } else { Strings.Rewards.addRewardCategory } }
                ?? Strings.Rewards.addRewardCategory),
            isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } }),
            presenting: naming
        ) { naming in
            TextField(Strings.Common.name, text: $typedName)
            Button(Strings.Common.cancel, role: .cancel) {}
            Button(Strings.Common.save) { save(naming) }
        }
        .confirmationDialog(
            Strings.Common.deleteNamed(deleting?.name ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { own in
            Button(Strings.Rewards.deleteRewardCategory, role: .destructive) {
                Log.store.perform("Deleting a Reward category", errorMessage: &errorMessage) { try rewards.delete(own) }
            }
        } message: { own in
            Text(Strings.Rewards.deleteRewardCategoryMessage(own.name))
        }
        .errorAlert(Strings.Rewards.couldntChange, message: $errorMessage)
    }

    /// The Reward category's name, with a menu to rename or delete it when it is one of the user's own.
    @ViewBuilder
    private func header(for reward: RewardCategory) -> some View {
        if reward.isOwn, let own = ownRewardCategories.first(where: { $0.key == reward.id }) {
            HStack {
                Text(reward.name)
                Spacer()
                Menu {
                    Button(Strings.Rewards.renameRewardCategory, systemImage: "pencil") {
                        typedName = own.name
                        naming = .rename(own)
                    }
                    Button(Strings.Rewards.deleteRewardCategory, systemImage: "trash", role: .destructive) {
                        deleting = own
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(Strings.Common.edit)
                }
            }
        } else {
            Text(reward.name)
        }
    }

    private func save(_ naming: Naming) {
        Log.store.perform("Naming a Reward category", errorMessage: &errorMessage) {
            switch naming {
            case .add: try rewards.add(named: typedName)
            case .rename(let own): try rewards.rename(own, to: typedName)
            }
        }
    }
}

/// One of the user's categories, with a menu of the Reward categories it can count as. A subcategory's first choice
/// is to follow its parent.
private struct RewardsAsRow: View {
    let category: Category
    let rewards: [RewardCategory]
    let set: (String?) -> Void

    var body: some View {
        Picker(selection: Binding(get: { choice }, set: { set($0) })) {
            if let parent = category.parent {
                Text(Strings.Categories.sameAsParent(parent.name, RewardCategory.named(parent.rewardsAs, in: rewards).name))
                    .tag(String?.none)
            }
            ForEach(rewards) { reward in
                Text(reward.name).tag(Optional(reward.id))
            }
        } label: {
            CategoryLabel(category: category)
        }
        .pickerStyle(.menu)
    }

    /// What the menu shows as chosen: the category's own, Everything else for a top-level one with none, or following
    /// its parent for a subcategory with none.
    private var choice: String? {
        RewardCategory.shownChoice(own: category.ownRewardsAs, isSubcategory: category.parent != nil)
    }
}

#Preview {
    NavigationStack {
        RewardCategoriesView()
    }
    .modelContainer(try! StoreOpening.open(inMemory: true))
}
