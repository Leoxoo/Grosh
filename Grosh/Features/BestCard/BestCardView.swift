import SwiftData
import SwiftUI

/// The Best Card tab: the Reward categories the user chose, in their order, as tiles, each with its Go-to card or else
/// the unarchived Card that earns the most on it (``BestCardTileView``). Search finds any Reward category, shown or not,
/// by its name or by the name of one of the user's categories counting as it. Customize chooses and orders the tiles.
/// Location, beside Category at the top, is still to come.
struct BestCardView: View {
    private enum Showing: Hashable {
        case category, location
    }

    @State private var showing = Showing.category
    @State private var query = ""
    @State private var isCustomizing = false
    @AppStorage(AppSettings.bestCardLayout) private var storedLayout
    @CurrentBestCard private var bestCard
    @Query private var categories: [Category]

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 200), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(selection: $showing) {
                        Text(Strings.BestCard.category).tag(Showing.category)
                        Text(Strings.BestCard.location).tag(Showing.location)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch showing {
                    case .category: tiles
                    case .location: location
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .tabRootTitle(Strings.BestCard.title)
            .searchable(text: $query, prompt: Text(Strings.BestCard.searchPrompt))
            .toolbar {
                if showing == .category {
                    ToolbarItem(placement: .primaryAction) {
                        Button(Strings.BestCard.customize, systemImage: "slider.horizontal.3") { isCustomizing = true }
                    }
                }
            }
            .sheet(isPresented: $isCustomizing) {
                BestCardCustomizeSheet(stored: $storedLayout, listed: $bestCard)
            }
            .navigationDestination(for: RewardCategory.self) { reward in
                BestCardRewardView(reward: reward)
            }
        }
    }

    @ViewBuilder private var tiles: some View {
        let shown = rewards
        if shown.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(shown) { reward in
                    NavigationLink(value: reward) {
                        BestCardTileView(tile: bestCard.tile(for: reward))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var location: some View {
        let placeholder = ComingSoon.location
        return ContentUnavailableView {
            Label(Strings.Common.comingSoon, systemImage: placeholder.systemImage)
        } description: {
            Text(placeholder.message)
        }
        .padding(.top, 40)
    }

    /// The tiles shown: the user's chosen ones, or while searching, every Reward category the search finds, in the
    /// user's order.
    private var rewards: [RewardCategory] {
        let listed = $bestCard
        let layout = BestCardLayout.read(storedLayout, listed: listed)
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return layout.shown(listed) }
        let own = listed.filter(\.isOwn)
        let names = Dictionary(
            RewardCategories.map(of: categories, own: own).map { ($0.reward.id, $0.categories.map(\.name)) },
            uniquingKeysWith: { first, _ in first }
        )
        return BestCardSearch.matches(text, in: layout.arranged(listed).map(\.reward), categoryNames: names)
    }
}

#Preview {
    BestCardView()
        .modelContainer(try! StoreOpening.open(inMemory: true))
}
