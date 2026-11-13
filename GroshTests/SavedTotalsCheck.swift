import SwiftData
import Testing
@testable import Grosh

/// Checks, once a test ends, that each store it made with ``TestStore`` holds the saved month totals a full count of
/// its transactions gives (``WalletMonthTotals/mismatches(in:)``, ADR-0013): a change that marked no month dirty fails
/// the test that made it. ``NamedInTheLogTrait``, which every suite carries, runs it around each test.
nonisolated enum SavedTotalsCheck {
    /// The stores the running test made.
    @TaskLocal static var stores: CheckedStores?

    /// Runs `test`, then records an issue for each saved total of its stores that differs from its transactions.
    static func around(_ test: @concurrent @Sendable () async throws -> Void) async throws {
        let stores = await CheckedStores()
        try await $stores.withValue(stores) {
            try await test()
        }
        await stores.check()
    }
}

/// The stores a test made, checked once it ends.
@MainActor
final class CheckedStores {
    private var containers: [ModelContainer] = []

    func add(_ container: ModelContainer) {
        containers.append(container)
    }

    func check() {
        for container in containers {
            do {
                for mismatch in try WalletMonthTotals.mismatches(in: container.mainContext) {
                    Issue.record(
                        """
                        The saved total of \(mismatch.wallet.name) for \(mismatch.monthRaw) is \(mismatch.savedCents), \
                        but its transactions add up to \(mismatch.countedCents): a change marked no month dirty
                        """
                    )
                }
            } catch {
                Issue.record(error, "Checking the saved month totals")
            }
        }
    }
}
