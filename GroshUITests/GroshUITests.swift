import Foundation
import OSLog
import XCTest

/// The smoke walk: Grosh as shipped, opened on the 16k store (about 16,000 transactions over six years), visiting every
/// tab and the main screens a user reaches from them, and adding an Expense. It fails when the app crashes or a screen
/// doesn't appear, naming the step and the screen. It checks that screens appear, not how fast: the benchmarks
/// (`GroshTests/PerformanceBenchmarks.swift`) time them. It does measure launch. How to run it, its steps, and what
/// only a Mac can check: `docs/agents/ui-smoke.md`.
final class GroshUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkEveryScreen() {
        let app = XCUIApplication()
        let walk = Walk(app)
        // The time in the note tells this walk's Expense apart from those of earlier walks today.
        let note = "Smoke walk \(Int(Date.now.timeIntervalSince1970))"
        _ = addUIInterruptionMonitor(withDescription: "Notifications prompt") { alert in
            MainActor.assumeIsolated { Walk.decline(alert) }
        }

        walk.step("Launch") {
            // The app makes the 16k store in its launch, before it has a screen, and no screen can be queried until
            // then. So it is launched to make the store, which quits once the store is made, and launched again to
            // open it.
            app.launchArguments = ["-GroshUITestStore", "make"]
            app.launch()
            XCTAssertTrue(
                app.wait(for: .notRunning, timeout: 900),
                "\(walk.current): the 16k store was still being made after 900 seconds."
            )
            app.launchArguments = ["-GroshUITestStore", "benchmark"]
            app.launch()
            walk.expect(app.navigationBars["Home"], "Home", timeout: 300)
            walk.declineNotificationsIfAsked()
        }
        walk.step("Launch → measure") {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                app.launch()
            }
            walk.expect(app.navigationBars["Home"], "Home")
        }
        walk.step("Home → open") {
            walk.expect(app.staticTexts["Total balance"], "Home's Total")
            walk.expect(app.staticTexts["Checking"].firstMatch, "Home's wallets")
        }
        walk.step("Transactions → open") {
            walk.openTab("Transactions")
            walk.expect(app.collectionViews.firstMatch.cells.firstMatch, "the transaction list")
        }
        walk.step("Transactions → scroll") {
            let list = app.collectionViews.firstMatch
            for _ in 0..<3 {
                list.swipeUp()
            }
            walk.expect(list.cells.firstMatch, "the transaction list")
        }
        walk.step("Transactions → open a transaction") {
            let row = walk.firstRowOnScreen(of: app.collectionViews.firstMatch, "the transaction list")
            // A row is a cell that holds its text in a child element, so the cell's own label is empty.
            let tapped = row.descendants(matching: .any).firstMatch.label
            row.tap()
            walk.expect(app.navigationBars["Transaction"], "the transaction's detail after tapping \"\(tapped)\"")
        }
        walk.step("Transactions → back") {
            walk.back(from: "Transaction", to: "Transactions")
        }
        walk.step("Budgets → open") {
            walk.openTab("Budgets")
        }
        walk.step("Account → open") {
            walk.openTab("Account")
        }
        walk.step("Wallets → open") {
            walk.open("Wallets", titled: "Wallets")
        }
        walk.step("Wallets → open a wallet") {
            let wallet = walk.element(startingWith: "Checking")
            walk.expect(wallet, "the wallet Checking")
            wallet.tap()
            let editor = app.navigationBars["Edit Wallet"]
            walk.expect(editor, "the wallet's editor")
            editor.buttons["Cancel"].tap()
            walk.expectGone(editor, "The wallet's editor")
        }
        walk.step("Recurring → open") {
            walk.back(from: "Wallets", to: "Account")
            walk.open("Recurring transactions", titled: "Recurring transactions")
        }
        walk.step("Debts & Loans → open") {
            walk.back(from: "Recurring transactions", to: "Account")
            walk.open("Debts & Loans", titled: "Debts & Loans")
        }
        walk.step("Recently Deleted → open") {
            walk.back(from: "Debts & Loans", to: "Account")
            walk.open("Recently Deleted", titled: "Recently Deleted")
        }
        walk.step("Home → add an Expense") {
            walk.openTab("Home")
            app.buttons["Add Transaction"].tap()
            let sheet = app.navigationBars["Add Transaction"]
            walk.expect(sheet, "the Add Transaction sheet")
            app.segmentedControls.buttons["Expense"].tap()
            // Typed cents first on the keypad, which has focus when the sheet opens: 4, 2 makes 0.42.
            app.buttons["4"].tap()
            app.buttons["2"].tap()

            let category = app.buttons.matching(identifier: "TransactionEditor.category").firstMatch
            walk.expect(category, "the Category row")
            category.tap()
            walk.expect(app.navigationBars["Category"], "the categories")
            let search = app.searchFields.firstMatch
            walk.expect(search, "the category search field")
            search.tap()
            search.typeText("Products")
            let products = app.buttons["Products"]
            walk.expect(products, "the category Products")
            products.tap()
            walk.expect(sheet, "the Add Transaction sheet")

            let save = sheet.buttons["Save"]
            if !save.isEnabled {
                // The suggested wallet is the last one used. An Expense from a wallet with a Card names the Card it
                // was paid with, and the 16k store's Checking has two.
                let card = app.buttons.matching(identifier: "TransactionEditor.card").firstMatch
                walk.expect(card, "the Card row")
                card.tap()
                let debit = app.buttons["Debit"]
                walk.expect(debit, "the Card Debit")
                debit.tap()
            }

            let noteField = app.descendants(matching: .any).matching(identifier: "TransactionEditor.note").firstMatch
            walk.expect(noteField, "the Note field")
            noteField.tap()
            noteField.typeText(note)
            XCTAssertTrue(
                save.isEnabled,
                "\(walk.current): Save is off, so the Expense still lacks a wallet, an amount, a category or its Card."
            )
            save.tap()
            walk.expectGone(sheet, "The Add Transaction sheet")
        }
        walk.step("Home → see the new Expense") {
            let row = walk.element(containing: note)
            walk.reveal(row, in: app.collectionViews.firstMatch)
            walk.expect(row, "the new Expense in Recent transactions")
        }
        // The search comes last. Its keyboard does not reliably go away, and it covers the tab bar, so nothing
        // after it can tap a tab.
        walk.step("Search → find a payee") {
            walk.openTab("Transactions")
            app.navigationBars["Transactions"].buttons["Search"].tap()
            let field = app.searchFields.firstMatch
            walk.expect(field, "the search field")
            field.tap()
            field.typeText("Sam")
            walk.expect(walk.element(containing: "Dinner with Sam"), "a dinner with Sam")
        }
    }
}

/// The walk's way around the app: each step logged for `tools/check-logs` and checked for a crash, each screen waited
/// for, and each failure naming the step and the screen.
@MainActor
private final class Walk {
    /// Where the steps go in the simulator's log. `tools/check-logs --ui` reads `begin <step>` and `end <step>` there
    /// to say which step an error was logged in, so both are logged at the default level with the name public.
    private static let steps = Logger(subsystem: "Leoxo.GroshUITests", category: "Steps")

    let app: XCUIApplication
    /// The step under way, which every failure names.
    private(set) var current = ""

    init(_ app: XCUIApplication) {
        self.app = app
    }

    /// Runs one step as an activity of the test, logged between `begin` and `end`, and fails it when Grosh is no longer
    /// running at its end.
    func step(_ name: String, _ body: () -> Void) {
        XCTContext.runActivity(named: name) { _ in
            Self.steps.notice("begin \(name, privacy: .public)")
            current = name
            body()
            XCTAssertEqual(
                app.state, .runningForeground,
                "\(name): Grosh is no longer running. It crashed, or an uncaught exception ended it."
            )
            Self.steps.notice("end \(name, privacy: .public)")
        }
    }

    /// Waits for `element`, and fails the step naming `what` when it hasn't appeared within `timeout` seconds. Ten
    /// seconds only runs out on a hang: how fast a screen opens is the benchmarks' job.
    func expect(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10, because reason: String? = nil) {
        if element.waitForExistence(timeout: timeout) { return }
        if app.state != .runningForeground {
            XCTFail(
                "\(current): Grosh is no longer running, so \(what) never appeared. "
                    + "It crashed, or an uncaught exception ended it."
            )
        } else {
            let why = reason.map { " \($0)" } ?? ""
            let bars = app.navigationBars.allElementsBoundByIndex.map(\.identifier)
            let shown = bars.isEmpty ? "none" : bars.joined(separator: ", ")
            XCTFail(
                "\(current): \(what) did not appear within \(Int(timeout)) seconds.\(why) "
                    + "Navigation bars on screen: \(shown)."
            )
        }
    }

    /// Waits for `element` to go, and fails the step naming `what` when it is still there after ten seconds.
    func expectGone(_ element: XCUIElement, _ what: String) {
        if element.waitForNonExistence(timeout: 10) { return }
        XCTFail("\(current): \(what) was still there after 10 seconds.")
    }

    /// Opens the tab called `name` and waits for its screen, which has the same title.
    func openTab(_ name: String) {
        app.tabBars.buttons[name].tap()
        expect(app.navigationBars[name], name)
    }

    /// Taps the row labelled `label` in the list on screen, scrolling to it first, and waits for the screen titled
    /// `title`.
    func open(_ label: String, titled title: String) {
        let row = app.buttons[label]
        reveal(row, in: app.collectionViews.firstMatch)
        expect(row, "the \(label) row")
        row.tap()
        expect(app.navigationBars[title], title)
    }

    /// Goes back from the screen titled `title` with its back button, the first in its navigation bar, and waits for
    /// the screen titled `parent`.
    func back(from title: String, to parent: String) {
        app.navigationBars[title].buttons.element(boundBy: 0).tap()
        expect(app.navigationBars[parent], parent)
    }

    /// Waits until `list` has stopped moving. A swipe leaves the list coasting, and a tap while it coasts only stops it,
    /// so the row under the tap is not opened.
    func settle(_ list: XCUIElement) {
        let first = list.cells.firstMatch
        guard first.exists else { return }
        var position = first.frame
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = first.frame
            if now == position { return }
            position = now
        }
    }

    /// Swipes `list` until `element` is on screen, down the list and then back up: a list makes only the rows in view.
    func reveal(_ element: XCUIElement, in list: XCUIElement) {
        for swipe in 0..<16 {
            if element.exists && element.isHittable { break }
            if swipe < 8 {
                list.swipeUp(velocity: .slow)
            } else {
                list.swipeDown(velocity: .slow)
            }
        }
        settle(list)
    }

    /// The first row of `list` that is on screen once the list has stopped moving, below the list's header and above
    /// the tab bar. A list keeps a few rows ready past its edges. Rows scroll under the header and the tab bar, which
    /// take the taps that land on them: such a row is hittable, but a tap on it opens nothing.
    func firstRowOnScreen(of list: XCUIElement, _ what: String) -> XCUIElement {
        settle(list)
        // The header takes up the top of the screen, so rows are taken from the middle of the screen down.
        let top = app.frame.midY
        let bottom = app.tabBars.firstMatch.frame.minY
        let rows = list.cells
        for index in 0..<min(rows.count, 30) {
            let row = rows.element(boundBy: index)
            // A day's header is a cell too, with no link to open: a transaction's row holds one.
            if row.isHittable, row.buttons.count > 0, row.frame.midY >= top, row.frame.midY <= bottom {
                return row
            }
        }
        XCTFail("\(current): no row of \(what) is on screen between its header and the tab bar.")
        return rows.firstMatch
    }

    /// The first element, of whatever kind, whose label holds `text`. A row's label joins all of its text.
    func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The first element, of whatever kind, whose label starts with `text`.
    func element(startingWith text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// Answers the notifications prompt when Grosh asks, as it does on its first launch on a simulator: the 16k store
    /// holds Loan reminders still to come. It comes just after Home, so this waits a moment for it.
    func declineNotificationsIfAsked() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            _ = Self.decline(alert)
        }
    }

    /// Taps Don't Allow on the notifications prompt, so no notification arrives over a screen the walk is about to tap.
    /// Says whether there was one to tap.
    static func decline(_ alert: XCUIElement) -> Bool {
        let dontAllow = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
        guard dontAllow.exists else { return false }
        dontAllow.tap()
        return true
    }
}
