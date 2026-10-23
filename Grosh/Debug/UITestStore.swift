#if DEBUG
import Foundation
import SwiftData
#if os(iOS)
import UIKit
#endif

/// The store a UI test opens the app on, asked for at launch with `-GroshUITestStore benchmark`: the 16k store
/// (``BenchmarkStore``) in the temporary directory, under a name of its own, so neither the user's store nor the
/// benchmarks' copy is ever opened. Its history runs up to today, so its name carries the day: the first launch of a
/// day makes a new one, which takes minutes, and removes the earlier days' ones. Animations are off while it is open,
/// so a test never waits on one. Only Debug builds read the argument. The walk that uses it: `docs/agents/ui-smoke.md`.
enum UITestStore {
    /// The launch argument's name. A launch argument `-name value` lands in the standard user defaults.
    static let argument = "GroshUITestStore"
    /// Six years of history, about 16,000 transactions: the 16k store, as the benchmarks make it.
    private static let years = 6
    private static let namePrefix = "GroshUITest-"

    /// The store a UI test asked for, made first when today's isn't there yet, or `nil` when the app was launched
    /// without the argument. A value other than `benchmark` is refused rather than opening the user's store.
    static func containerIfAsked() throws -> ModelContainer? {
        guard let name = UserDefaults.standard.string(forKey: argument) else { return nil }
        guard name == "benchmark" else { throw UITestStoreError.unknown(name) }
        #if os(iOS)
        UIView.setAnimationsEnabled(false)
        #endif
        let url = URL.temporaryDirectory.appending(path: "\(namePrefix)\(CalendarDay.today.rawValue).store")
        removeEarlierStores(keeping: url)
        try BenchmarkStore.prepare(at: url, years: years)
        let container = try BenchmarkStore.open(at: url)
        // Seeded as the app's own store is (GroshStore.makeSeededContainer).
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        try CategorySeeder.restoreMissingDefaults(in: container.mainContext)
        return container
    }

    /// Removes the stores made on earlier days, which a new one each day would otherwise pile up beside.
    private static func removeEarlierStores(keeping url: URL) {
        let folder = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let earlier = names.filter { $0.hasPrefix(namePrefix) && $0.hasSuffix(".store") && $0 != url.lastPathComponent }
        for name in earlier {
            BenchmarkStore.remove(at: folder.appending(path: name))
        }
    }
}

/// Why the app couldn't open the store a UI test asked for.
nonisolated enum UITestStoreError: Error, Equatable {
    /// `-GroshUITestStore` named a store there is none of.
    case unknown(String)
}

extension UITestStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknown(let name): "No UI test store is called “\(name)”. The one there is: benchmark."
        }
    }
}
#endif
