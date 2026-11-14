import OSLog
import Testing

/// Logs each test's name as it begins and ends, so `tools/check-logs` can say which test was running when Grosh logged
/// an error, a fault or a runtime issue (`docs/agents/log-check.md`). A test logs `begin <Suite>/<test>` and
/// `end <Suite>/<test>`, and its suite `begin <Suite>` and `end <Suite>`, in subsystem `Leoxo.GroshTests`, category
/// `Tests`. Every suite carries it, `@Suite(.namedInTheLog)`, and a new one should too: a message logged in a suite
/// without it carries only its time.
///
/// Around each test it also checks the saved month totals of every ``TestStore`` the test made (``SavedTotalsCheck``).
struct NamedInTheLogTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    /// `@concurrent` on the method and its closure matches Swift Testing's `provideScope`, which is built without
    /// `NonisolatedNonsendingByDefault`. This target's approachable concurrency setting would otherwise run both on the
    /// caller's actor, and the conformance would not match.
    @concurrent
    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        // `Suite/test()`, with any suites around it: the name tools/check gives a failing test.
        let name = test.id.nameComponents.joined(separator: "/")
        testNames.notice("begin \(name, privacy: .public)")
        defer { testNames.notice("end \(name, privacy: .public)") }
        if test.isSuite {
            try await function()
        } else {
            try await SavedTotalsCheck.around(function)
        }
    }
}

extension Trait where Self == NamedInTheLogTrait {
    /// Logs the name of each test in the suite as it begins and ends, for `tools/check-logs`.
    static var namedInTheLog: Self { Self() }
}

/// `tools/check-logs` reads exactly this subsystem and category, and the `begin` and `end` wording.
private let testNames = Logger(subsystem: "Leoxo.GroshTests", category: "Tests")
