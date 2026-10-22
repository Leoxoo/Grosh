import SwiftData
import SwiftUI

@main
struct GroshApp: App {
    private let container: ModelContainer
    private let textThemInbox = TextThemInbox()
    /// The notification center holds its delegate weakly, so the app keeps it.
    private let reminderActions: ReminderActionHandler
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try GroshStore.makeSeededContainer()
        } catch {
            fatalError("Couldn't open the Grosh store: \(error)")
        }
        reminderActions = ReminderActionHandler.install(inbox: textThemInbox, context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .presentsTextThem(textThemInbox)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Items in Recently Deleted that have waited 30 days are removed for good, and Recurring transactions
                    // make the days that came due while the app was closed, whenever the app opens or comes back to the
                    // foreground; nothing runs in the background.
                    if phase == .active {
                        try? RecentlyDeleted.purgeExpired(in: container.mainContext)
                        try? RecurringTransaction.catchUp(in: container.mainContext)
                    }
                }
        }
        .modelContainer(container)
        .commands {
            NewTransactionCommands()
        }
    }
}
