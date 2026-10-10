import Foundation
import SwiftData

/// The user's categories: the rules for arranging, editing, hiding, merging and deleting them.
/// Views call this instead of changing ``Category`` objects directly, so every rule lives in one place.
struct CategoryCatalog {
    let context: ModelContext

    // MARK: Reading

    /// The categories of `type` in tree order: each parent followed by its subcategories.
    /// Without `includingHidden`, hidden categories and the subcategories of hidden parents are left out.
    func categories(of type: CategoryType, includingHidden: Bool = true) throws -> [Category] {
        let typeRaw = type.rawValue
        let all = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.typeRaw == typeRaw }))
        return Self.tree(of: type, from: all, includingHidden: includingHidden)
    }

    /// Puts the categories of `type` found in `all` in tree order, as ``categories(of:includingHidden:)`` does.
    /// For views that already hold the categories from a query.
    static func tree(of type: CategoryType, from all: [Category], includingHidden: Bool = true) -> [Category] {
        let topLevel = all.filter { $0.type == type && $0.parent == nil }
        let tree = sorted(topLevel).flatMap { [$0] + sorted($0.children ?? []) }
        return includingHidden ? tree : tree.filter { !$0.isHiddenInTree }
    }

    /// The categories of `type` the user may file a transaction under, in tree order. Hidden categories, and those
    /// only the app itself files under (transfers, payments, Starting balance), are left out.
    func pickerCategories(of type: CategoryType) throws -> [Category] {
        try categories(of: type, includingHidden: false).filter { $0.lockedRole?.isOfferedInPicker != false }
    }

    // MARK: Adding and editing

    /// Adds a category at the end of its parent's subcategories, or of its type's top-level categories.
    @discardableResult
    func add(_ draft: CategoryDraft) throws -> Category {
        let category = try insert(draft)
        try context.save()
        return category
    }

    /// ``add(_:)`` without the save, for a caller that saves once after adding many, such as an import. The same
    /// rules apply.
    @discardableResult
    func insert(_ draft: CategoryDraft) throws -> Category {
        try checkPlacement(draft, for: nil)
        let name = try checkedName(draft, for: nil)
        let category = Category(
            name: name,
            type: draft.type,
            symbolName: draft.symbolName,
            color: draft.color,
            parent: draft.parent,
            sortOrder: try nextOrder(of: draft.type, under: draft.parent)
        )
        context.insert(category)
        return category
    }

    /// Saves the draft's fields onto `category`. A category that changes type takes its subcategories along,
    /// which is only allowed while none of them has transactions.
    func update(_ category: Category, to draft: CategoryDraft) throws {
        if category.isLocked {
            try updateIcon(of: category, to: draft)
            return
        }
        let isRetyped = draft.type != category.type
        let children = category.children ?? []
        if isRetyped, hasTransactions(category) { throw CategoryRuleError.hasTransactions }
        try checkPlacement(draft, for: category)
        let name = try checkedName(draft, for: category)
        if isRetyped {
            for child in children {
                try checkNameIsFree(child.name, in: draft.type, except: child)
            }
        }

        category.name = name
        category.symbolName = draft.symbolName
        category.color = draft.color
        if isRetyped || draft.parent != category.parent {
            category.sortOrder = try nextOrder(of: draft.type, under: draft.parent)
            category.parent = draft.parent
        }
        if isRetyped {
            for retyped in [category] + children {
                retyped.type = draft.type
            }
        }
        try context.save()
    }

    /// The categories a category of `type` may be placed under, in tree order. `category` is the one being edited,
    /// if any.
    func parentOptions(of type: CategoryType, for category: Category?) throws -> [Category] {
        try categories(of: type).filter { candidate in
            (try? checkPlacement(CategoryDraft(type: type, parent: candidate), for: category)) != nil
        }
    }

    /// A locked category's icon is all that may change.
    private func updateIcon(of category: Category, to draft: CategoryDraft) throws {
        guard draft.name == category.name, draft.type == category.type, draft.parent == category.parent else {
            throw CategoryRuleError.locked
        }
        category.symbolName = draft.symbolName
        category.color = draft.color
        try context.save()
    }

    /// Checks the draft's type and parent. `category` is the one being edited, if any.
    private func checkPlacement(_ draft: CategoryDraft, for category: Category?) throws {
        guard draft.type.isUserManaged else { throw CategoryRuleError.fixedType }
        guard let parent = draft.parent else { return }
        guard parent != category else { throw CategoryRuleError.sameCategory }
        guard !parent.isLocked else { throw CategoryRuleError.locked }
        guard parent.type == draft.type else { throw CategoryRuleError.differentType }
        guard parent.parent == nil, (category?.children ?? []).isEmpty else { throw CategoryRuleError.tooDeep }
    }

    /// The draft's name without surrounding spaces, once it is known to be unique within the draft's type.
    /// `category` is the one being edited, which may keep its own name.
    private func checkedName(_ draft: CategoryDraft, for category: Category?) throws -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryRuleError.nameRequired }
        try checkNameIsFree(name, in: draft.type, except: category)
        return name
    }

    private func checkNameIsFree(_ name: String, in type: CategoryType, except category: Category?) throws {
        let taken = try categories(of: type).contains {
            $0 != category && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        guard !taken else { throw CategoryRuleError.nameTaken }
    }

    // MARK: Hiding

    /// Hides a category from the picker (its subcategories too) or brings it back. Its transactions keep it.
    func setHidden(_ category: Category, _ isHidden: Bool) throws {
        guard !category.isLocked else { throw CategoryRuleError.locked }
        category.isHidden = isHidden
        try context.save()
    }

    // MARK: Merging

    /// The categories `source` may be merged into, in tree order.
    func mergeTargets(for source: Category) throws -> [Category] {
        try categories(of: source.type).filter { (try? checkMerge(source, into: $0)) != nil }
    }

    /// Moves every transaction of `source` into `target`, then removes `source`. A parent's subcategories move
    /// under `target`, after its own.
    func merge(_ source: Category, into target: Category) throws {
        try checkMerge(source, into: target)
        for transaction in source.transactions ?? [] {
            transaction.category = target
        }
        var nextOrder = nextChildOrder(under: target)
        for child in Self.sorted(source.children ?? []) {
            child.parent = target
            child.sortOrder = nextOrder
            nextOrder += 1
        }
        context.delete(source)
        try context.save()
    }

    private func checkMerge(_ source: Category, into target: Category) throws {
        guard !source.isLocked, !target.isLocked else { throw CategoryRuleError.locked }
        guard source != target else { throw CategoryRuleError.sameCategory }
        guard source.type == target.type else { throw CategoryRuleError.differentType }
        // A parent's subcategories end up under the target, so the target must be top-level.
        guard (source.children ?? []).isEmpty || target.parent == nil else { throw CategoryRuleError.tooDeep }
    }

    // MARK: Deleting

    func canDelete(_ category: Category) -> Bool {
        (try? checkDelete(category)) != nil
    }

    /// Deletes a category that has no transactions, along with its subcategories.
    func delete(_ category: Category) throws {
        try checkDelete(category)
        for child in category.children ?? [] {
            context.delete(child)
        }
        context.delete(category)
        try context.save()
    }

    private func checkDelete(_ category: Category) throws {
        guard !category.isLocked else { throw CategoryRuleError.locked }
        guard !hasTransactions(category) else { throw CategoryRuleError.hasTransactions }
    }

    /// Whether the category or any of its subcategories has transactions.
    func hasTransactions(_ category: Category) -> Bool {
        ([category] + (category.children ?? [])).contains { !($0.transactions ?? []).isEmpty }
    }

    // MARK: Helpers

    private func nextChildOrder(under parent: Category) -> Int {
        ((parent.children ?? []).map(\.sortOrder).max() ?? -1) + 1
    }

    private func nextOrder(of type: CategoryType, under parent: Category?) throws -> Int {
        if let parent { return nextChildOrder(under: parent) }
        let topLevel = try categories(of: type).filter { $0.parent == nil }
        return (topLevel.map(\.sortOrder).max() ?? -1) + 1
    }

    private static func sorted(_ categories: [Category]) -> [Category] {
        categories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

extension Category {
    /// Hidden itself, or a subcategory of a hidden parent.
    var isHiddenInTree: Bool { isHidden || parent?.isHidden == true }

    /// Outgoing transfer or Incoming transfer: one half of a Transfer, which never carries a Card.
    var isTransferHalf: Bool { lockedRole == .outgoingTransfer || lockedRole == .incomingTransfer }
}

extension CategoryType {
    /// Expense and Income categories are the user's own; Debt/Loan and system categories are fixed.
    var isUserManaged: Bool { self == .expense || self == .income }
}

extension LockedRole {
    /// Whether the user picks this category by hand. The rest are filed by their own flows: Transfer,
    /// Record payment, and a new wallet's Starting balance.
    var isOfferedInPicker: Bool {
        switch self {
        case .otherIncome, .otherExpense, .loan, .debt: true
        case .outgoingTransfer, .incomingTransfer, .debtCollection, .repayment, .startingBalance: false
        }
    }
}
