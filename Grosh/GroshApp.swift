import SwiftData
import SwiftUI

@main
struct GroshApp: App {
    private let container: ModelContainer
    private let textThemInbox = TextThemInbox()
    /// The notification center holds its delegate weakly, so the app keeps it.
    private let reminderActions: ReminderActionHandler
    @Environment(\.scenePhase) private var scenePhase
    /// The day the screens treat as today: the real one, moved on when it changes while the app is open.
    @State private var today = CalendarDay.today

    init() {
        container = Self.openStore()
        reminderActions = ReminderActionHandler.install(inbox: textThemInbox, context: container.mainContext)
    }

    /// The user's store or, when a UI test asks for it, the 16k store in its place (UITestStore). A Debug build then
    /// checks the saved month totals against a full count of the transactions once, and logs an error when they differ
    /// (ADR-0013).
    private static func openStore() -> ModelContainer {
        let container: ModelContainer
        do {
            #if DEBUG
            container = try UITestStore.containerIfAsked() ?? StoreOpening.open()
            #else
            container = try StoreOpening.open()
            #endif
        } catch {
            fatalError("Couldn't open the Grosh store: \(error)")
        }
        #if DEBUG
        WalletMonthTotals.logMismatches(in: container.mainContext)
        #endif
        return container
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .presentsTextThem(textThemInbox)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Items in Recently Deleted that have waited 30 days are removed for good, and Recurring transactions
                    // make the days that came due while the app was closed, whenever the app opens or comes back to the
                    // foreground; nothing runs in the background. The day moves on first, in case it changed meanwhile.
                    if phase == .active {
                        let today = refreshToday()
                        Signpost.interval("Launch") {
                            Log.store.attempt("Removing what Recently Deleted kept for good") {
                                try RecentlyDeleted.purgeExpired(in: container.mainContext)
                            }
                            Log.recurring.attempt("Making the Recurring transactions that came due") {
                                try RecurringTransaction.catchUp(through: today, in: container.mainContext)
                            }
                        }
                    }
                }
                .environment(\.today, today)
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

    @discardableResult
    private func refreshToday() -> CalendarDay {
        let now = CalendarDay.today
        if now != today { today = now }
        return now
    }
}
