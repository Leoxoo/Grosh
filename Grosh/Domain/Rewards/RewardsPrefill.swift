import Foundation
import SwiftData

/// The one-time start of the user's Rewards as: when a store first gets Reward categories, the default tree's
/// categories (``DefaultCategories``) found by name are set to the Reward category they stand for. It never runs on
/// that store again, and never changes a category whose Rewards as is already set.
enum RewardsPrefill {
    /// The milestone a store keeps once it was prefilled.
    static let milestone = "rewardsAsPrefilled"

    /// Which default categories each Reward category stands for: the rewards pipeline's `APP_CATEGORIES`
    /// (`tools/rewards-catalog/pipeline/extract.py`).
    static let defaultNames: [String: [String]] = [
        "dining": ["Food & Beverage", "Café", "Restaurants"],
        "groceries": ["Products"],
        "gas": ["Petrol", "Other Fuel"],
        "travel": ["Travel"],
        "transit": ["Taxi", "Public Transport", "Parking Fees"],
        "streaming": ["Streaming Service", "Apps"],
        "entertainment": ["Entertainment", "Games", "Movies", "Cultural/Animals"],
        "drugstores": ["Pharmacy"],
        "home-improvement": ["Home Improvement"],
        "fitness": ["Sports"],
        "phone-internet": ["Phone Bill", "Internet Bill"],
        "utilities": ["Water Bill", "Electricity Bill", "Gas Bill", "Valet/Trash Bill"],
        "department-stores": ["Clothing", "Footwear", "Accessories"],
    ]

    /// Prefills the store's Rewards as, unless it was prefilled before. Saves when it did.
    static func prefillIfNeeded(in context: ModelContext) throws {
        let name = milestone
        var reached = FetchDescriptor<StoreMilestone>(predicate: #Predicate { $0.name == name })
        reached.fetchLimit = 1
        guard try context.fetchCount(reached) == 0 else { return }
        let rewardByName = Dictionary(
            defaultNames.flatMap { reward, names in names.map { ($0, reward) } }, uniquingKeysWith: { first, _ in first }
        )
        let expense = CategoryType.expense.rawValue
        let categories = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.typeRaw == expense }))
        for category in categories where category.offersRewardsAs && category.ownRewardsAs == nil {
            if let reward = rewardByName[category.name] {
                category.ownRewardsAs = reward
            }
        }
        context.insert(StoreMilestone(name: milestone))
        try context.save()
    }
}
