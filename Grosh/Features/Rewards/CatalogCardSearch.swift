import SwiftUI

/// A searchable list of the rewards catalog's cards, matching name and bank, with Custom card first when it is offered.
/// Add Card opens on it, and so does linking a Card that has no rewards yet. Use inside a `NavigationStack`.
struct CatalogCardSearch: View {
    /// Whether Custom card is the first choice, as when adding a Card.
    var offersCustomCard = false
    /// What was picked: a catalog card, or `nil` for Custom card.
    let pick: (CatalogCard?) -> Void

    @Environment(\.rewardsCatalog) private var catalog
    @State private var searchText = ""

    var body: some View {
        let found = catalog.search(searchText)
        List {
            if offersCustomCard {
                Section {
                    Button {
                        pick(nil)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Strings.Rewards.customCard)
                            Text(Strings.Rewards.customCardDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                ForEach(found) { card in
                    Button {
                        pick(card)
                    } label: {
                        CatalogCardLabel(card: card)
                    }
                }
            } footer: {
                if !found.isEmpty {
                    Text(Strings.Rewards.catalogFooter)
                }
            }
        }
        .tint(.primary)
        .overlay {
            if found.isEmpty && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: Strings.Rewards.searchCatalog)
    }
}

/// ``CatalogCardSearch`` in a sheet of its own, titled Choose Catalog Card, with Cancel: how a Card that exists is
/// linked or changed to another entry.
struct CatalogCardSearchSheet: View {
    /// What was picked. Picking or cancelling closes the sheet.
    let pick: (CatalogCard) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CatalogCardSearch { entry in
                dismiss()
                if let entry { pick(entry) }
            }
            .navigationTitle(Strings.Rewards.chooseCatalogCard)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
            }
        }
    }
}

/// A catalog card's name, with its bank, network and annual fee under it, and "No longer in the catalog" for an entry
/// a newer catalog dropped.
struct CatalogCardLabel: View {
    let card: CatalogCard
    var isNoLongerInCatalog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.name)
            Text(details)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if isNoLongerInCatalog {
                Text(Strings.Rewards.noLongerInCatalog)
                    .capsuleBadge(.secondary, on: .secondary)
            }
        }
    }

    private var details: String {
        let fee: String? = switch card.annualFee {
        case let fee? where fee > 0: String(localized: Strings.Rewards.annualFee(CardRateText.dollars(fee)))
        case .some: String(localized: Strings.Rewards.noAnnualFee)
        case nil: nil
        }
        return [card.issuer, card.network, fee].compactMap(\.self).joined(separator: " · ")
    }
}
