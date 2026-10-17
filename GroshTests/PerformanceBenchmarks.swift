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
/// Each line it prints starts with `BENCH`, then the median, fastest and slowest of the timed runs in milliseconds; with
/// `TEST_RUNNER_GROSH_BENCHMARK_OUT` set to a path, the lines are added to that file too. The store is made on the first
/// run of the day, which takes a few minutes.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GROSH_BENCHMARK"] != nil))
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
            let firstDay = MonthGraphHistory.firstDay(
                earliest: try context.fetch(MonthGraphHistory.earliestCounted), forgiven: forgiven
            )
            _ = MonthGraph.months(from: firstDay, today: today)
            let history = try context.fetch(MonthGraphHistory.transactions(for: month)) + forgiven
            let counted = history.compactMap(\.countedAmount)
            for side in SpentOrIncome.allCases {
                _ = MonthGraph(side, of: counted, countingFrom: firstDay, recurring: recurring, in: month, today: today)
            }
        }
    }
}

// MARK: - Timing

/// Runs `body` once to warm up, then `runs` times, and prints the median, fastest and slowest run.
@MainActor
@discardableResult
func time(_ name: String, runs: Int = 7, _ body: () throws -> Void) rethrows -> Double {
    try body()
    var samples: [Double] = []
    for _ in 0..<runs {
        let start = ContinuousClock.now
        try body()
        samples.append(milliseconds(ContinuousClock.now - start))
    }
    return report(name, samples)
}

@discardableResult
func report(_ name: String, _ samples: [Double]) -> Double {
    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    let line = String(
        format: "BENCH %-60@ median %8.2f ms   min %8.2f   max %8.2f   (n=%d)",
        name as NSString, median, sorted.first ?? 0, sorted.last ?? 0, samples.count
    )
    print(line)
    if let path = ProcessInfo.processInfo.environment["GROSH_BENCHMARK_OUT"],
       let handle = FileHandle(forWritingAtPath: path) ?? {
           FileManager.default.createFile(atPath: path, contents: nil)
           return FileHandle(forWritingAtPath: path)
       }() {
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }
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

// MARK: - The store

/// A store on disk with years of history, made once and reused by every benchmark.
@MainActor
enum BenchmarkStore {
    static func open(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: GroshStore.schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: GroshStore.schema, configurations: configuration)
    }

    /// Makes the store at `url` unless it is there already, made today.
    static func prepare(at url: URL, years: Int) throws {
        let stamp = url.appendingPathExtension("made")
        let today = String(CalendarDay.today.rawValue)
        if (try? String(contentsOf: stamp, encoding: .utf8)) == today { return }
        for suffix in ["", "-shm", "-wal", ".made"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
        }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appending(path: ".GroshBenchmark-v1_SUPPORT"))
        let start = ContinuousClock.now
        let container = try open(at: url)
        try fill(container.mainContext, years: years)
        try today.write(to: stamp, atomically: true, encoding: .utf8)
        print("BENCH made the store in \(ContinuousClock.now - start)")
    }

    private static func fill(_ context: ModelContext, years: Int) throws {
        try CategorySeeder.seedIfNeeded(in: context)
        var random = SplitMix(seed: 42)
        let categories = try context.fetch(FetchDescriptor<Grosh.Category>())
        let expenses = categories.filter { $0.type == .expense && !$0.isLocked }
        let incomes = categories.filter { $0.type == .income && !$0.isLocked }
        func role(_ role: LockedRole) -> Grosh.Category { categories.first { $0.lockedRole == role }! }

        let wallets = ["Checking", "Savings", "Cash", "Travel"].enumerated().map { index, name in
            let wallet = Wallet(name: name, sortOrder: index)
            context.insert(wallet)
            return wallet
        }
        let archived = Wallet(name: "Old bank", sortOrder: 9)
        archived.isArchived = true
        context.insert(archived)

        let photoCard = Card(name: "Sapphire", kind: .credit, payingWallet: wallets[0])
        photoCard.imageData = cardPhoto()
        let plainCard = Card(name: "Debit", kind: .debit, payingWallet: wallets[0], color: .green)
        context.insert(photoCard)
        context.insert(plainCard)

        let today = CalendarDay.today
        let first = CalendarMonth(today).adding(months: -12 * years).firstDay
        let notes = ["", "", "", "Lunch", "Groceries for the week", "Coffee", "Taxi home", "Gift", "Dinner with Sam"]
        var day = first
        var count = 0
        let lastDay = today.adding(days: 20)
        while day <= lastDay {
            for _ in 0..<random.next(in: 4...10) {
                let wallet = wallets[random.next(in: 0...9) < 7 ? 0 : random.next(in: 1...3)]
                let transaction = Grosh.Transaction(
                    amount: Money(cents: -random.next(in: 150...15_000)), day: day, wallet: wallet,
                    category: expenses[random.next(in: 0...(expenses.count - 1))],
                    note: notes[random.next(in: 0...(notes.count - 1))]
                )
                switch random.next(in: 0...9) {
                case 0...2: transaction.card = photoCard
                case 3: transaction.card = plainCard
                default: break
                }
                transaction.isExcludedFromReport = random.next(in: 0...49) == 0
                context.insert(transaction)
                count += 1
            }
            if day.day == 1 || day.day == 15 {
                context.insert(Grosh.Transaction(
                    amount: Money(cents: random.next(in: 250_000...400_000)), day: day, wallet: wallets[0],
                    category: incomes[0]
                ))
                let link = UUID()
                let out = Grosh.Transaction(amount: Money(cents: -50_000), day: day, wallet: wallets[0], category: role(.outgoingTransfer))
                let into = Grosh.Transaction(amount: Money(cents: 50_000), day: day, wallet: wallets[1], category: role(.incomingTransfer))
                out.linkID = link
                into.linkID = link
                context.insert(out)
                context.insert(into)
                count += 3
            }
            if day.day == 10, random.next(in: 0...2) == 0 {
                let loan = Grosh.Transaction(amount: Money(cents: -random.next(in: 2_000...50_000)), day: day, wallet: wallets[2], category: role(.loan))
                loan.withName = ["Sam", "Alex", "Jo"][random.next(in: 0...2)]
                loan.isExcludedFromReport = true
                loan.linkID = UUID()
                loan.reminderDay = day.adding(days: 30)
                context.insert(loan)
                count += 1
            }
            if count % 2_000 < 12 { try context.save() }
            day = day.adding(days: 1)
        }

        // Some waiting in Recently Deleted, not yet due to be removed.
        let recent = try context.fetch(Grosh.Transaction.recent(limit: 150, asOf: today))
        for transaction in recent.suffix(100) { transaction.deletedAt = .now.addingTimeInterval(-5 * 86_400) }

        // Recurring transactions, dealt with through today so opening the app has nothing to make.
        for index in 0..<12 {
            let schedule = RecurringTransaction()
            schedule.name = "Schedule \(index)"
            schedule.amountCents = random.next(in: 500...150_000)
            schedule.wallet = wallets[0]
            schedule.category = expenses[index * 3 % expenses.count]
            schedule.kind = [.bill, .subscription, .regular, .purchase][index % 4]
            schedule.amountVaries = index % 4 == 0
            if schedule.kind == .subscription { schedule.iconData = cardPhoto(width: 256, height: 256) }
            schedule.schedule = RepeatSchedule(
                start: first.adding(days: index), rule: RepeatRule(unit: .month, every: 1),
                end: .forever, monthlyDay: .sameDay
            )
            schedule.handledThrough = today
            context.insert(schedule)
        }
        try context.save()
        print("BENCH store holds \(try context.fetchCount(FetchDescriptor<Grosh.Transaction>())) transactions")
    }

    /// A photographic-looking Card image: JPEG of a noisy gradient, as ``CroppedPhoto`` stores it.
    private static func cardPhoto(width: Int = 960, height: Int = 605) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        var random = SplitMix(seed: 7)
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let noise = Double(random.next(in: 0...40)) / 255
                context.setFillColor(CGColor(
                    red: Double(x) / Double(width) * 0.6 + noise, green: 0.3 + noise, blue: Double(y) / Double(height), alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}

/// A seeded random number generator, so every store made has the same history.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return range.lowerBound + Int(z % UInt64(range.count))
    }
}

#endif
