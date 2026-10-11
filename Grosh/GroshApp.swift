import SwiftData
import SwiftUI

@main
struct GroshApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try GroshStore.makeSeededContainer()
        } catch {
            fatalError("Couldn't open the Grosh store: \(error)")
        }
        // Items in Recently Deleted are removed for good once they have waited 30 days; nothing runs in the background.
        try? RecentlyDeleted.purgeExpired(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .commands {
            NewTransactionCommands()
        }
    }
}
