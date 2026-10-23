import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Grosh

#if os(iOS)
import UIKit

/// Times what the user waits for — opening the app, opening each screen, scrolling, searching, saving — against a store
/// with years of history, so a change can be measured before and after. Skipped in a normal test run. Run it on an
/// optimized build, one test at a time, with:
///
///     TEST_RUNNER_GROSH_BENCHMARK=1 xcodebuild test -scheme Grosh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///         SWIFT_OPTIMIZATION_LEVEL=-O -parallel-testing-enabled NO -only-testing:GroshTests/PerformanceBenchmarks
///
/// Each line it prints starts with `BENCH`, then the median, fastest and slowest of the timed runs in milliseconds and
/// the step's budget; with `TEST_RUNNER_GROSH_BENCHMARK_OUT` set to a path, the lines are added to that file too. The
/// store is made on the first run of the day, which takes a few minutes.
///
/// A step whose median is over its budget in `BenchmarkBudgets` fails the test, and so does a step with no budget; on
/// a setup other than the one the budgets were measured on, a step over its budget is a warning instead. The run ends
/// with a summary line. See `docs/agents/benchmarks.md`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GROSH_BENCHMARK"] != nil), .checkingBudgets)
struct PerformanceBenchmarks {
    /// About 16,000 transactions over six years, as a long-time user (or a Money Lover import) has.
    static let years = 6
    static let storeURL = URL.temporaryDirectory.appending(path: "GroshBenchmark-v1.store")
    /// An iPhone 17 Pro's screen in points.
    static let screen = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test func launchToFirstFrame() throws {
        try BenchmarkStore.prepare(at: Self.storeURL, years: Self.years)
        try time("launch: open store + startup work") {
            let container = try BenchmarkStore.open(at: Self.storeURL)
            try CategorySeeder.seedIfNeeded(in: container.mainContext)
            try CategorySeeder.restoreMissingDefaults(in: container.mainContext)
            try RecentlyDeleted.purgeExpired(in: container.mainContext)
            try RecurringTransaction.catchUp(in: container.mainContext)
        }
        try time("launch: open store + startup work + first frame of Home") {
            let container = try BenchmarkStore.open(at: Self.storeURL)
            try CategorySeeder.seedIfNeeded(in: container.mainContext)
            try CategorySeeder.restoreMissingDefaults(in: container.mainContext)
            try RecentlyDeleted.purgeExpired(in: container.mainContext)
            try RecurringTransaction.catchUp(in: container.mainContext)
            _ = Hosted(RootView(), container: container)
        }
    }

    @Test func openingScreens() throws {
        try BenchmarkStore.prepare(at: Self.storeURL, years: Self.years)
        // A store already open and Home on screen, as they are once the app is running.
        let container = try BenchmarkStore.open(at: Self.storeURL)
        let app = Hosted(RootView(), container: container)
        defer { withExtendedLifetime(app) {} }

        try time("open Home (cold store)") {
            let cold = try BenchmarkStore.open(at: Self.storeURL)
            _ = Hosted(HomeView(), container: cold)
        }
        time("open Home") { _ = Hosted(HomeView(), container: container) }
        time("open Transactions") { _ = Hosted(TransactionsView(), container: container) }
        time("open Account") { _ = Hosted(AccountView(), container: container) }
        time("open Wallets") { _ = Hosted(NavigationStack { WalletListView() }, container: container) }
        time("open Recurring") { _ = Hosted(NavigationStack { RecurringTransactionsView() }, container: container) }
        time("open Debts & Loans") { _ = Hosted(NavigationStack { DebtsLoansView() }, container: container) }
        time("open Recently Deleted") { _ = Hosted(NavigationStack { RecentlyDeletedView() }, container: container) }
        let card = try #require(try container.mainContext.fetch(FetchDescriptor<Card>()).first { $0.imageData != nil })
        time("open a Card's transactions") {
            _ = Hosted(NavigationStack { CardTransactionsView(card: card) }, container: container)
        }
    }

    /// What scrolling costs: each row coming into view is made and drawn, so this draws a few hundred rows at once in a
    /// window tall enough to hold them all, and prints the cost of a screenful (13 rows).
    @Test func rowsComingIntoView() throws {
        try BenchmarkStore.prepare(at: Self.storeURL, years: Self.years)
        let container = try BenchmarkStore.open(at: Self.storeURL)
        let recent = try container.mainContext.fetch(Grosh.Transaction.recent(limit: 2_000, asOf: .today))
        let mixed = Array(recent.prefix(300))
        let withPhoto = Array(recent.filter { $0.card?.imageData != nil }.prefix(300))
        for (name, rows) in [("transaction rows", mixed), ("transaction rows paid with a Card with a photo", withPhoto)] {
            let samples = (0..<6).map { _ in
                let start = ContinuousClock.now
                _ = Hosted(
                    List(rows) { TransactionRow(transaction: $0) }, container: container,
                    frame: CGRect(x: 0, y: 0, width: 402, height: CGFloat(rows.count) * 64)
                )
                return milliseconds(ContinuousClock.now - start) / Double(rows.count) * 13
            }
            report("scroll: a screenful (13) of \(name)", Array(samples.dropFirst()))
        }
    }

    /// What saving costs while Home and the Transactions tab are open, as they stay once visited: each screen reading
    /// from the store reads again and redraws.
    @Test func savingATransaction() throws {
        try BenchmarkStore.prepare(at: Self.storeURL, years: Self.years)
        let container = try BenchmarkStore.open(at: Self.storeURL)
        let context = container.mainContext
        let home = Hosted(RootView(), container: container)
        let transactions = Hosted(TransactionsView(), container: container)
        let wallet = try #require(try context.fetch(Wallet.unarchived).first)
        let category = try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.type == .expense })
        var samples: [Double] = []
        for _ in 0..<6 {
            let start = ContinuousClock.now
            let added = Grosh.Transaction(amount: Money(cents: -4_20), day: .today, wallet: wallet, category: category)
            context.insert(added)
            try context.save()
            home.settle()
            transactions.settle()
            samples.append(milliseconds(ContinuousClock.now - start))
            context.delete(added)
            try context.save()
            home.settle()
            transactions.settle()
        }
        report("save a new transaction with Home and Transactions open", Array(samples.dropFirst()))
    }

    /// The work behind each keystroke in search, which looks through every transaction.
    @Test func searching() throws {
        try BenchmarkStore.prepare(at: Self.storeURL, years: Self.years)
        let container = try BenchmarkStore.open(at: Self.storeURL)
        let all = try container.mainContext.fetch(Grosh.Transaction.notDeleted)
        for text in ["Lunch", "12"] {
            time("search for \"\(text)\" and group the results by day") {
                let results = all.matching(TransactionFilter(searchText: text))
                _ = TransactionDay.days(of: results, scheduled: [])
            }
        }
    }

    /// The work behind stepping the Transactions tab back to an older month, which redraws the whole list.
    @Test func olderMonths() throws {
        try BenchmarkStore.prepare(at: Self.storeURL, years: Self.years)
        let container = try BenchmarkStore.open(at: Self.storeURL)
        let all = try container.mainContext.fetch(Grosh.Transaction.notDeleted)
        let today = CalendarDay.today
        let old = Period.month(CalendarMonth(today).adding(months: -30))
        let entries = NotDeletedTransactions.Store.of(container.mainContext).entries
        time("Transactions body work for a month 2½ years back") {
            let filter = TransactionFilter()
            let selected = filter.transactions(in: .total, from: entries)
            _ = TimeRange.month.periods(from: selected.firstDay, today: today)
            let shown = filter.listed(from: all, selected: selected, on: old.days(today: today))
            _ = PeriodSummary(of: selected, in: old, today: today)
            _ = TransactionDay.days(of: shown, scheduled: [])
        }
        try time("Home Month graph work for a month 2½ years back") {
            let context = container.mainContext
            let month = CalendarMonth(today).adding(months: -30)
            let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
            let forgiven = try context.fetch(MonthGraphHistory.forgiven)
            let otherIncome = try context.otherCategory(.income)
            let firstDay = MonthGraphHistory.firstDay(
                earliest: try context.fetch(MonthGraphHistory.earliestCounted), forgiven: forgiven,
                otherIncome: otherIncome
            )
            _ = MonthGraph.months(from: firstDay, today: today)
            let history = try context.fetch(MonthGraphHistory.transactions(for: month)) + forgiven
            let counted = history.compactMap { $0.countedAmount(otherIncome: otherIncome) }
            for side in SpentOrIncome.allCases {
                _ = MonthGraph(side, of: counted, countingFrom: firstDay, recurring: recurring, in: .month(month), today: today)
            }
        }
    }
}

// MARK: - Timing

/// Runs `body` once to warm up, then `runs` times, and reports the median, fastest and slowest run against the step's
/// budget. A failure is recorded on the line that called this.
@MainActor
@discardableResult
func time(
    _ name: String, runs: Int = 7, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Void
) rethrows -> Double {
    try body()
    var samples: [Double] = []
    for _ in 0..<runs {
        let start = ContinuousClock.now
        try body()
        samples.append(milliseconds(ContinuousClock.now - start))
    }
    return report(name, samples, sourceLocation: sourceLocation)
}

/// Prints a step's median, fastest and slowest sample and its budget, then holds the median to the budget
/// (`BenchmarkBudgets.check`).
@discardableResult
func report(_ name: String, _ samples: [Double], sourceLocation: SourceLocation = #_sourceLocation) -> Double {
    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    let step = BenchmarkStep(name: name, median: median, budget: BenchmarkBudgets.steps[name])
    printBench(
        String(
            format: "BENCH %-60@ median %8.2f ms   min %8.2f   max %8.2f   (n=%d)",
            name as NSString, median, sorted.first ?? 0, sorted.last ?? 0, samples.count
        ) + step.budgetColumn
    )
    BenchmarkBudgets.check(step, sourceLocation: sourceLocation)
    return median
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
}

// MARK: - Hosting

/// A SwiftUI view on screen in its own window, laid out and drawn once: what the user sees when the screen opens.
@MainActor
final class Hosted {
    let window: UIWindow
    let controller: UIViewController

    init(_ view: some View, container: ModelContainer, frame: CGRect = PerformanceBenchmarks.screen) {
        window = UIWindow(frame: frame)
        controller = UIHostingController(rootView: view.modelContainer(container))
        window.rootViewController = controller
        window.isHidden = false
        settle()
    }

    deinit {
        MainActor.assumeIsolated {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// Lays the screen out, lets SwiftUI apply what that schedules, and commits the frame.
    func settle() {
        for _ in 0..<2 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.current.run(until: .now)
        }
        CATransaction.flush()
    }
}

#endif
