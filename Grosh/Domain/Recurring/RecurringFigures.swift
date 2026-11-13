import SwiftData

/// What a Recurring screen shows of each schedule beyond its own values: the amount its transactions start at (a
/// varying Bill's estimate, read from the store, ``RecurringSchedules``) and a Purchase's progress (from its attached
/// transactions). Worked out once for the screen and handed to its rows, rather than by each row as it draws.
struct RecurringFigures {
    private let schedules: RecurringSchedules
    private let progress: [PersistentIdentifier: PurchaseProgress]

    init(_ schedules: [RecurringTransaction]) {
        var progress: [PersistentIdentifier: PurchaseProgress] = [:]
        for recurring in schedules {
            progress[recurring.persistentModelID] = recurring.purchaseProgress
        }
        self.schedules = RecurringSchedules(schedules)
        self.progress = progress
    }

    /// What `recurring`'s transactions start at now, one of the schedules the figures were worked out for.
    func startingAmount(of recurring: RecurringTransaction) -> Money {
        schedules.startingAmount(of: recurring)
    }

    /// `recurring`'s progress when it is a Purchase (``RecurringTransaction/purchaseProgress``), otherwise `nil`.
    func purchaseProgress(of recurring: RecurringTransaction) -> PurchaseProgress? {
        progress[recurring.persistentModelID]
    }
}
