import Foundation
import Testing

// MARK: - The budgets

/// How long each step `PerformanceBenchmarks` times may take on the 16k store, and the setup those budgets were
/// measured on. Milliseconds only mean something on the Mac, simulator, OS and Xcode that measured them, so on that
/// setup a step over its budget fails the benchmarks, and on any other it prints a warning and passes. A step with no
/// budget fails on every setup, so a new benchmark can't go unchecked. `docs/agents/benchmarks.md` says how to read a
/// failure and how to record a budget.
enum BenchmarkBudgets {
    /// The setup the budgets were measured on, copied from the `BENCH setup:` line of a benchmark run on it.
    static let recordedSetup = "Mac16,7 (Apple M4 Pro) / iPhone18,1 simulator / iOS 27.0 (24A434) / Xcode 27.1 (27A9275) / optimized"

    /// Each step's budget in milliseconds: the most the median of its timed runs may be, which is the median measured
    /// plus headroom for noise. The key is the step's name as it is passed to `time` or `report`:
    ///
    ///     "<step name>": <milliseconds>,
    static let steps: [String: Double] = [
        "Home Month graph work for a month 2½ years back": 58,
        "Transactions body work for a month 2½ years back": 15,
        "launch: open store + startup work": 23,
        "launch: open store + startup work + first frame of Home": 666,
        "open Account": 45,
        "open Debts & Loans": 74,
        "open Home": 174,
        "open Home (cold store)": 592,
        "open Recently Deleted": 73,
        "open Recurring": 110,
        "open Transactions": 148,
        "open Wallets": 150,
        "open a Card's transactions": 95,
        "save a new transaction with Home and Transactions open": 185,
        "scroll: a screenful (13) of transaction rows": 38,
        "scroll: a screenful (13) of transaction rows paid with a Card with a photo": 41,
        "search for \"12\" and group the results by day": 65,
        "search for \"Lunch\" and group the results by day": 62,
    ]
}

// MARK: - A step against its budget

/// One timed step: its name, the median of its timed runs in milliseconds, and the budget it is held to, if it has one.
struct BenchmarkStep: Equatable, Sendable {
    var name: String
    var median: Double
    var budget: Double?

    /// How far the median is from the budget as a fraction of it: 0.41 is 41% over, -0.25 is 25% under. Nil when the
    /// step has no budget.
    var excess: Double? { budget.map { (median - $0) / $0 } }

    var isOverBudget: Bool { budget.map { median > $0 } ?? false }

    /// `open Home: 212 ms > budget 150 ms (+41%)`, or nil when the step is not over its budget.
    var overBudgetLine: String? {
        guard let budget, let excess, isOverBudget else { return nil }
        // A step a hair over its budget still reads as over it, never as +0%.
        let percent = String(format: "+%.0f%%", max(1, (excess * 100).rounded()))
        return "\(name): \(Self.formatted(median)) > budget \(Self.formatted(budget)) (\(percent))"
    }

    /// What to do about a step with no budget, or nil when it has one.
    var missingBudgetLine: String? {
        guard budget == nil else { return nil }
        let measured = Self.formatted(median)
        return "no budget recorded for \(name) (median \(measured)): add it to GroshTests/BenchmarkBudgets.swift"
    }

    /// The end of the step's `BENCH` line: its budget, and how far the median is over (+) or under (-) it.
    var budgetColumn: String {
        guard let budget, let excess else { return "   no budget" }
        return String(format: "   budget %8.2f ms (%+.0f%%)", budget, excess * 100)
    }

    /// Milliseconds as the messages give them: whole from 100 up, to a tenth below.
    private static func formatted(_ milliseconds: Double) -> String {
        let rounded = String(format: milliseconds >= 100 ? "%.0f" : "%.1f", milliseconds)
        return (rounded.hasSuffix(".0") ? String(rounded.dropLast(2)) : rounded) + " ms"
    }
}

// MARK: - The setup

/// The Mac, simulator, OS and Xcode a run is on, and whether its build is optimized, in one line. The budgets are
/// recorded against it because the milliseconds they hold mean something only on the setup that measured them.
///
/// Nothing is set by hand. The simulator is a process on the Mac, so the Mac is read from the kernel they share, the
/// simulated iPhone from the `SIMULATOR_` environment, the OS from `ProcessInfo`, and Xcode from the version it wrote
/// into the Info.plist of what it built. A part that can't be read shows as unknown, the same on every run.
enum BenchmarkSetup {
    /// The line the benchmarks print after `BENCH setup:`, which `BenchmarkBudgets.recordedSetup` is a copy of.
    static let current = [mac, simulator, operatingSystem, xcode, optimization].joined(separator: " / ")

    /// `2640` is Xcode 26.4 and `2641` is 26.4.1: how Xcode writes its version into what it builds.
    static func xcodeVersion(_ code: String) -> String {
        guard let number = Int(code), number >= 100 else { return code }
        let minor = number / 10 % 10
        let patch = number % 10
        return "\(number / 100).\(minor)" + (patch == 0 ? "" : ".\(patch)")
    }

    private static let environment = ProcessInfo.processInfo.environment

    /// The Mac's model and chip, as the kernel reports them to the simulator.
    private static var mac: String {
        var name = sysctlString("hw.model") ?? "unknown Mac"
        if let chip = sysctlString("machdep.cpu.brand_string") { name += " (\(chip))" }
        return name
    }

    /// The simulated iPhone's model, which stays the same when Xcode runs a clone of the simulator.
    private static var simulator: String {
        environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) simulator" } ?? "not a simulator"
    }

    private static var operatingSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var name = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion != 0 { name += ".\(version.patchVersion)" }
        if let build = environment["SIMULATOR_RUNTIME_BUILD_VERSION"] { name += " (\(build))" }
        #if os(iOS)
        return "iOS " + name
        #else
        return "OS " + name
        #endif
    }

    /// Xcode's version and build, from the `DTXcode` and `DTXcodeBuild` entries it writes into the Info.plist of the
    /// app and of the test bundle.
    private static var xcode: String {
        let bundles = [Bundle.main, Bundle(for: BundleAnchor.self)]
        func entry(_ key: String) -> String? {
            bundles.compactMap { $0.object(forInfoDictionaryKey: key) as? String }.first
        }
        guard let code = entry("DTXcode") else { return "unknown Xcode" }
        var name = "Xcode " + xcodeVersion(code)
        if let build = entry("DTXcodeBuild") { name += " (\(build))" }
        return name
    }

    /// A build without optimization is much slower, so it is a setup of its own. An assertion runs its condition only
    /// when assertions are on, which is when the build is not optimized.
    private static var optimization: String {
        var assertionsAreOn = false
        assert({ () -> Bool in assertionsAreOn = true; return true }())
        return assertionsAreOn ? "unoptimized" : "optimized"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
}

/// Anything in this test bundle, for `Bundle(for:)` to find the bundle by.
private final class BundleAnchor {}

// MARK: - A run

/// The latest timing of each step, kept for the summary. A step is kept under its name, so a step timed again replaces
/// its earlier timing. The tests that time them run one at a time on the main actor, but nothing here relies on that
/// or on the order they run in.
private final class TimedSteps: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [String: BenchmarkStep] = [:]

    var all: [BenchmarkStep] { lock.withLock { Array(steps.values) } }
    func record(_ step: BenchmarkStep) { lock.withLock { steps[step.name] = step } }
}

extension BenchmarkBudgets {
    private static let timed = TimedSteps()

    /// Whether this run is on the setup the budgets were measured on, so that a step over its budget fails.
    static let isRecordedSetup = recordedSetup.trimmingCharacters(in: .whitespacesAndNewlines) == BenchmarkSetup.current

    /// Starts a run: prints the setup it is on.
    static func begin() {
        printBench("BENCH setup: \(BenchmarkSetup.current)")
        if !isRecordedSetup {
            printBench(
                "BENCH warning: this is not the setup the budgets were recorded on (\(recordedSetup)), "
                    + "so a step over its budget is reported here but does not fail."
            )
        }
    }

    /// Counts the step in the run and holds it to its budget. A step with no budget fails. One over its budget fails on
    /// the recorded setup and is a warning on any other, so the same numbers show either way.
    static func check(_ step: BenchmarkStep, sourceLocation: SourceLocation) {
        timed.record(step)
        if let line = step.missingBudgetLine {
            Issue.record("\(line)", sourceLocation: sourceLocation)
        } else if let line = step.overBudgetLine {
            if isRecordedSetup {
                Issue.record("\(line)", sourceLocation: sourceLocation)
            } else {
                printBench("BENCH warning: \(line)")
            }
        }
    }

    /// Ends the run with one line listing every step over its budget, or without one. It is made from the steps timed,
    /// not from which test ran last, so the order the tests run in does not matter.
    static func finish() {
        printBench(summary(of: timed.all, enforced: isRecordedSetup))
    }

    /// The summary line. The steps over their budget come worst first, whatever order `steps` is in. When `enforced` is
    /// false they are warnings, and the line says so.
    static func summary(of steps: [BenchmarkStep], enforced: Bool) -> String {
        guard !steps.isEmpty else { return "BENCH summary: no steps were timed" }
        let over = steps.filter(\.isOverBudget).sorted { first, second in
            let (firstExcess, secondExcess) = (first.excess ?? 0, second.excess ?? 0)
            return firstExcess == secondExcess ? first.name < second.name : firstExcess > secondExcess
        }
        let withoutBudget = steps.filter { $0.budget == nil }.map(\.name).sorted()
        var findings: [String] = []
        if !over.isEmpty {
            let warnings = enforced ? "" : " (warnings only: not the recorded setup)"
            let lines = over.compactMap(\.overBudgetLine).joined(separator: "; ")
            findings.append("\(over.count) over budget\(warnings): \(lines)")
        }
        if !withoutBudget.isEmpty {
            findings.append("\(withoutBudget.count) with no budget: " + withoutBudget.joined(separator: ", "))
        }
        let count = "\(steps.count) \(steps.count == 1 ? "step" : "steps") timed"
        return "BENCH summary: \(count), " + (findings.isEmpty ? "all within budget" : findings.joined(separator: ". "))
    }
}

/// Brackets a benchmark suite's run: the setup is printed before its first test and the summary after its last. Swift
/// Testing calls a suite trait's scope once around all the suite's tests, so no test has to run last.
struct BenchmarkBudgetsTrait: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    /// `@concurrent` on the method and its closure matches Swift Testing's `provideScope`, which is built without
    /// `NonisolatedNonsendingByDefault`. This target's approachable concurrency setting would otherwise run both on the
    /// caller's actor, and the conformance would not match.
    @concurrent
    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        BenchmarkBudgets.begin()
        defer { BenchmarkBudgets.finish() }
        try await function()
    }
}

extension Trait where Self == BenchmarkBudgetsTrait {
    /// Holds the suite's timed steps to their budgets and ends its run with a summary of those over.
    static var checkingBudgets: Self { Self() }
}

/// Prints a line of benchmark output, and adds it to the file `GROSH_BENCHMARK_OUT` names when that is set.
func printBench(_ line: String) {
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
}

// MARK: - Tests

/// What decides whether a benchmark run passes, on timings made up here. The benchmarks themselves are skipped in a
/// normal test run.
struct BenchmarkBudgetTests {
    @Test func aStepOverItsBudgetNamesTheMedianTheBudgetAndHowFarOver() {
        let step = BenchmarkStep(name: "open Home", median: 212, budget: 150)

        #expect(step.isOverBudget)
        #expect(step.overBudgetLine == "open Home: 212 ms > budget 150 ms (+41%)")
        #expect(step.missingBudgetLine == nil)
    }

    @Test func aStepBarelyOverItsBudgetIsNeverSaidToBeZeroPercentOver() {
        let step = BenchmarkStep(name: "open Home", median: 150.2, budget: 150)

        #expect(step.overBudgetLine == "open Home: 150 ms > budget 150 ms (+1%)")
    }

    @Test(arguments: [100.0, 149.9, 150.0])
    func aStepWithinItsBudgetHasNothingToReport(median: Double) {
        let step = BenchmarkStep(name: "open Home", median: median, budget: 150)

        #expect(!step.isOverBudget)
        #expect(step.overBudgetLine == nil)
        #expect(step.missingBudgetLine == nil)
    }

    @Test func aStepWithNoBudgetSaysWhereToAddOne() {
        let step = BenchmarkStep(name: "open Home", median: 212, budget: nil)

        #expect(!step.isOverBudget)
        #expect(step.overBudgetLine == nil)
        #expect(
            step.missingBudgetLine
                == "no budget recorded for open Home (median 212 ms): add it to GroshTests/BenchmarkBudgets.swift"
        )
    }

    @Test func aBenchLineEndsWithTheBudgetAndHowFarTheMedianIsFromIt() {
        let over = BenchmarkStep(name: "open Home", median: 212, budget: 150)
        let under = BenchmarkStep(name: "open Home", median: 120, budget: 160)
        let unbudgeted = BenchmarkStep(name: "open Home", median: 120, budget: nil)

        #expect(over.budgetColumn == "   budget   150.00 ms (+41%)")
        #expect(under.budgetColumn == "   budget   160.00 ms (-25%)")
        #expect(unbudgeted.budgetColumn == "   no budget")
    }

    @Test func theSummaryListsEveryStepOverItsBudgetWorstFirstWhateverOrderTheyRanIn() {
        let steps = [
            BenchmarkStep(name: "open Account", median: 40, budget: 50),
            BenchmarkStep(name: "open Transactions", median: 130, budget: 100),
            BenchmarkStep(name: "open Home", median: 212, budget: 150),
        ]
        let summary = "BENCH summary: 3 steps timed, 2 over budget: "
            + "open Home: 212 ms > budget 150 ms (+41%); open Transactions: 130 ms > budget 100 ms (+30%)"

        #expect(BenchmarkBudgets.summary(of: steps, enforced: true) == summary)
        #expect(BenchmarkBudgets.summary(of: Array(steps.reversed()), enforced: true) == summary)
    }

    @Test func onAnotherSetupTheSummaryCallsTheStepsOverTheirBudgetWarnings() {
        let steps = [BenchmarkStep(name: "open Home", median: 212, budget: 150)]

        #expect(
            BenchmarkBudgets.summary(of: steps, enforced: false)
                == "BENCH summary: 1 step timed, 1 over budget (warnings only: not the recorded setup): "
                + "open Home: 212 ms > budget 150 ms (+41%)"
        )
    }

    @Test func theSummaryNamesTheStepsWithNoBudget() {
        let steps = [
            BenchmarkStep(name: "open Wallets", median: 80, budget: nil),
            BenchmarkStep(name: "open Home", median: 212, budget: nil),
            BenchmarkStep(name: "open Account", median: 40, budget: 50),
        ]

        #expect(
            BenchmarkBudgets.summary(of: steps, enforced: true)
                == "BENCH summary: 3 steps timed, 2 with no budget: open Home, open Wallets"
        )
    }

    @Test func theSummaryOfStepsAllWithinTheirBudgetsSaysSo() {
        let steps = [BenchmarkStep(name: "open Account", median: 40, budget: 50)]

        #expect(BenchmarkBudgets.summary(of: steps, enforced: true) == "BENCH summary: 1 step timed, all within budget")
        #expect(BenchmarkBudgets.summary(of: [], enforced: true) == "BENCH summary: no steps were timed")
    }

    @Test(arguments: [("2640", "26.4"), ("2641", "26.4.1"), ("1500", "15.0"), ("beta", "beta")])
    func xcodeVersionsReadTheWayXcodeNamesThem(code: String, version: String) {
        #expect(BenchmarkSetup.xcodeVersion(code) == version)
    }

    @Test func everyBudgetIsAPositiveNumberOfMilliseconds() {
        for (name, budget) in BenchmarkBudgets.steps {
            #expect(budget > 0 && budget.isFinite, "The budget for \(name) is \(budget).")
        }
    }

    @Test func budgetsComeWithTheSetupTheyWereMeasuredOn() {
        func parts(_ setup: String) -> Int { setup.components(separatedBy: " / ").count }

        #expect(
            BenchmarkBudgets.steps.isEmpty || parts(BenchmarkBudgets.recordedSetup) == parts(BenchmarkSetup.current),
            "Set BenchmarkBudgets.recordedSetup to the text after BENCH setup: in the run the budgets were measured on."
        )
    }
}
