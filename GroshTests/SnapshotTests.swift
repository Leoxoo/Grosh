#if os(iOS)
import Foundation
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Grosh

/// Snapshots of each transaction row kind (Expense, Income, Transfer, Split, Reimbursement) and of Home with its
/// Month graph, each in light, dark and the accessibility text size AX3. Every screen is drawn as of
/// `MonthGraphFixture.today`, from fixed transactions, in English (United States) on a 402 × 874 screen, so the same
/// tree gives the same images on any day. The references are PNG files in `__Snapshots__`, recorded on the developer's
/// Mac: `docs/agents/testing.md` says how to record them and review a change.
@MainActor
@Suite(.serialized, .enabled(if: snapshotsRunHere))
struct SnapshotTests {
    @Test func expenseRow() throws {
        let fixture = try MonthGraphFixture()
        let expense = try fixture.record(-4_520, "Products", on: fixture.today)
        assertLooks(of: TransactionRow(transaction: expense).padding(), in: fixture)
    }

    @Test func incomeRow() throws {
        let fixture = try MonthGraphFixture()
        let income = try fixture.record(300_000, "Salary", .income, on: fixture.today)
        assertLooks(of: TransactionRow(transaction: income).padding(), in: fixture)
    }

    @Test func transferRow() throws {
        let fixture = try MonthGraphFixture()
        let savings = Wallet(name: "Savings")
        fixture.context.insert(savings)
        var draft = TransferDraft(day: fixture.today)
        draft.from = fixture.checking
        draft.to = savings
        draft.amount = Money(cents: 20_000)
        let transfer = try Transfer.create(draft, in: fixture.context)
        assertLooks(of: TransactionRow(transaction: transfer.outgoing).padding(), in: fixture)
    }

    /// An Expense split in two. The part filed under Restaurants is the row drawn; the original keeps the rest.
    @Test func splitRow() throws {
        let fixture = try MonthGraphFixture()
        let original = try fixture.record(-8_610, "Products", on: fixture.today)
        var draft = SplitDraft(splitting: original)
        var restaurants = draft.newPart()
        restaurants.amount = Money(cents: 2_610)
        restaurants.category = try fixture.category("Restaurants")
        draft.addPart(restaurants)
        let part = try original.split(draft, in: fixture.context)[0]
        assertLooks(of: TransactionRow(transaction: part).padding(), in: fixture)
    }

    @Test func reimbursementRow() throws {
        let fixture = try MonthGraphFixture()
        let dinner = try fixture.record(-6_200, "Restaurants", on: fixture.today)
        try Reimbursement.add(
            ReimbursementDraft(amount: Money(cents: 2_000), day: fixture.today, note: "Dinner share"), to: dinner,
            in: fixture.context
        )
        assertLooks(of: TransactionRow(transaction: dinner).padding(), in: fixture)
    }

    /// Home on October 12, with September for the Month graph's Average and a few transactions in each month.
    @Test func homeWithItsMonthGraph() throws {
        let fixture = try MonthGraphFixture()
        try fixture.record(300_000, "Salary", .income, on: day(2026, 9, 1))
        try fixture.record(-120_000, "Rentals", on: day(2026, 9, 2))
        try fixture.record(-14_000, "Restaurants", on: day(2026, 9, 20))
        try fixture.record(300_000, "Salary", .income, on: day(2026, 10, 1))
        try fixture.record(-120_000, "Rentals", on: day(2026, 10, 2))
        try fixture.record(-4_520, "Products", on: day(2026, 10, 3))
        try fixture.record(-2_750, "Taxi", on: day(2026, 10, 5))
        try fixture.record(-8_610, "Products", on: day(2026, 10, 9))
        try fixture.context.save()
        assertLooks(of: HomeView(), in: fixture)
    }

    /// Draws `screen` in light, dark and the accessibility text size, as of the fixture's day, and compares each with
    /// its reference. The looks share the environment and the screen size, so only appearance and text size differ.
    private func assertLooks(
        of screen: some View, in fixture: MonthGraphFixture,
        filePath: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        // Home's preferences come from a suite of their own, so a Total hidden on the simulator doesn't change Home.
        let framed = screen
            .environment(\.today, fixture.today)
            .environment(\.locale, Locale(identifier: "en_US"))
            .defaultAppStorage(UserDefaults(suiteName: "GroshSnapshotTests") ?? .standard)
            .modelContainer(fixture.container)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(uiColor: .systemBackground))
        let looks: [(name: String, traits: UITraitCollection)] = [
            ("light", Self.traits(.light, .large)),
            ("dark", Self.traits(.dark, .large)),
            ("accessibility", Self.traits(.light, .accessibilityExtraLarge)),
        ]
        for look in looks {
            assertSnapshot(
                of: framed,
                as: .image(
                    drawHierarchyInKeyWindow: true, layout: .fixed(width: 402, height: 874), traits: look.traits
                ),
                named: look.name, file: filePath, testName: testName, line: line
            )
        }
    }

    /// The appearance and text size of one look, set explicitly so the simulator's own settings don't change it.
    private static func traits(_ style: UIUserInterfaceStyle, _ size: UIContentSizeCategory) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(preferredContentSizeCategory: size),
        ])
    }
}

/// Whether the suite runs. CI sets `CI`, and the workflow passes it to the test process as `TEST_RUNNER_CI`, since
/// xcodebuild forwards only `TEST_RUNNER_` variables. Where it is set, the suite is skipped and one line says so.
private let snapshotsRunHere: Bool = {
    guard ProcessInfo.processInfo.environment["CI"] == nil else {
        print("Snapshot tests skipped on CI: their references are recorded on a Mac (docs/agents/testing.md).")
        return false
    }
    return true
}()
#endif
