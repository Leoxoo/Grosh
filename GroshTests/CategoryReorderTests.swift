import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Reordering categories in Account → Categories: the top-level categories of a type among themselves, and a parent's
/// subcategories within it.
@MainActor
@Suite(.namedInTheLog)
struct CategoryReorderTests {
    private let fixture: CategoryFixture

    init() throws {
        fixture = try CategoryFixture()
    }

    private func expenseParents() throws -> [Grosh.Category] {
        CategoryCatalog.parents(of: .expense, from: try fixture.context.fetch(FetchDescriptor<Grosh.Category>()))
    }

    @Test func draggingACategoryUpPutsItWhereItWasDropped() throws {
        let parents = try expenseParents()
        let before = parents.map(\.name)

        try fixture.catalog.move(parents, fromOffsets: [2], toOffset: 0)

        let expected: [String] = [before[2], before[0], before[1]] + Array(before[3...])
        #expect(try expenseParents().map(\.name) == expected)
    }

    @Test func draggingACategoryDownPutsItWhereItWasDropped() throws {
        let parents = try expenseParents()
        let before = parents.map(\.name)

        // SwiftUI's onMove reports the drop offset in the list before the move.
        try fixture.catalog.move(parents, fromOffsets: [0], toOffset: 2)

        let expected: [String] = [before[1], before[0]] + Array(before[2...])
        #expect(try expenseParents().map(\.name) == expected)
    }

    @Test func aCategoryTakesItsSubcategoriesAlongWhenItMoves() throws {
        let bills = try fixture.category("Bills & Utilities")
        let parents = try expenseParents()
        let index = try #require(parents.firstIndex(of: bills))

        try fixture.catalog.move(parents, fromOffsets: [index], toOffset: 0)

        let subcategories = CategoryCatalog.subcategories(of: bills).map(\.name)
        let tree = try fixture.catalog.categories(of: .expense).map(\.name)
        #expect(Array(tree.prefix(1 + subcategories.count)) == ["Bills & Utilities"] + subcategories)
    }

    @Test func draggingASubcategoryReordersItWithinItsParent() throws {
        let bills = try fixture.category("Bills & Utilities")
        let subcategories = CategoryCatalog.subcategories(of: bills)
        let before = subcategories.map(\.name)

        try fixture.catalog.move(subcategories, fromOffsets: [before.count - 1], toOffset: 0)

        let expected: [String] = [before[before.count - 1]] + Array(before[..<(before.count - 1)])
        #expect(CategoryCatalog.subcategories(of: bills).map(\.name) == expected)
    }

    @Test func aCategoryAddedAfterReorderingGoesLast() throws {
        let parents = try expenseParents()
        try fixture.catalog.move(parents, fromOffsets: [0], toOffset: parents.count)

        try fixture.catalog.add(CategoryDraft(name: "Stationery", type: .expense))

        #expect(try expenseParents().last?.name == "Stationery")
    }
}
