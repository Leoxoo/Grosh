import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A category's own Kind and the default Kind it gives its Recurring transactions. A subcategory with no Kind of its own
/// follows its parent; one that has set its own keeps it.
@MainActor
struct CategoryKindTests {
    private let store: CategoryFixture

    init() throws {
        store = try CategoryFixture()
    }

    @Test func aSeededCategoryIsRegularAndItsSubcategoriesFollowIt() throws {
        let parent = try store.category("Bills & Utilities")
        let child = try store.category("Phone Bill")
        #expect(parent.ownKind == .regular)
        #expect(child.ownKind == nil)
        #expect(child.defaultKind == .regular)
    }

    @Test func aSubcategoryFollowsItsParentUntilItSetsItsOwn() throws {
        let parent = try store.category("Bills & Utilities")
        let child = try store.category("Phone Bill")
        parent.ownKind = .bill
        #expect(child.defaultKind == .bill)
        parent.ownKind = .subscription
        #expect(child.defaultKind == .subscription)
    }

    @Test func aSubcategoryKeepsItsOwnKindWhateverItsParentBecomes() throws {
        let parent = try store.category("Bills & Utilities")
        let child = try store.category("Phone Bill")
        child.ownKind = .purchase
        parent.ownKind = .bill
        #expect(child.defaultKind == .purchase)
    }

    @Test func aRegularSubcategoryStaysRegularUnderABillParent() throws {
        let parent = try store.category("Bills & Utilities")
        let child = try store.category("Phone Bill")
        child.ownKind = .regular
        parent.ownKind = .bill
        #expect(child.defaultKind == .regular)
    }

    @Test func aNewSubcategoryWithNoKindFollowsItsParent() throws {
        let parent = try store.category("Bills & Utilities")
        parent.ownKind = .bill
        let added = try store.catalog.add(CategoryDraft(name: "Gas Meter", type: .expense, parent: parent))
        #expect(added.ownKind == nil)
        #expect(added.defaultKind == .bill)
    }

    @Test func theEditorSetsAndClearsACategorysOwnKind() throws {
        let parent = try store.category("Bills & Utilities")
        let child = try store.category("Phone Bill")
        parent.ownKind = .bill
        var draft = CategoryDraft(child)
        draft.ownKind = .purchase
        try store.catalog.update(child, to: draft)
        #expect(child.defaultKind == .purchase)
        draft.ownKind = nil
        try store.catalog.update(child, to: draft)
        #expect(child.defaultKind == .bill)
    }
}
