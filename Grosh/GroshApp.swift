import SwiftData
import SwiftUI

@main
struct GroshApp: App {
    private let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    /// The day the screens treat as today: the real one, moved on when it changes while the app is open.
    @State private var today = CalendarDay.today

    init() {
        do {
            #if DEBUG
            // A UI test can ask for the 16k store in place of the user's (UITestStore).
            if let uiTestStore = try UITestStore.containerIfAsked() {
                container = uiTestStore
                return
            }
            #endif
            container = try GroshStore.makeSeededContainer()
        } catch {
            fatalError("Couldn't open the Grosh store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Items in Recently Deleted that have waited 30 days are removed for good, and Recurring transactions
                    // make the days that came due while the app was closed, whenever the app opens or comes back to the
                    // foreground; nothing runs in the background.
                    if phase == .active {
                        try? RecentlyDeleted.purgeExpired(in: container.mainContext)
                        try? RecurringTransaction.catchUp(in: container.mainContext)
                    }
                }
                .environment(\.today, today)
                // A day that changed while the app was in the background.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refreshToday() }
                }
                // Midnight passing while the app is open.
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    refreshToday()
                }
        }
        .modelContainer(container)
        .commands {
            NewTransactionCommands()
        }
    }

    /// Moves `today` on to the real day when it has changed.
    private func refreshToday() {
        let now = CalendarDay.today
        if now != today { today = now }
    }
}
