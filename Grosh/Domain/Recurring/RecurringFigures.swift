import SwiftData

/// What a Recurring screen shows of each schedule beyond its own values: the amount its transactions start at (a
/// varying Bill's estimate, read from the store) and a Purchase's progress (from its attached transactions). Worked out
/// once for the screen and handed to its rows, rather than by each row as it draws.
struct RecurringFigures {
    private let startingAmounts: [PersistentIdentifier: Money]
    private let progress: [PersistentIdentifier: PurchaseProgress]

    init(_ schedules: [RecurringTransaction]) {
        var startingAmounts: [PersistentIdentifier: Money] = [:]
        var progress: [PersistentIdentifier: PurchaseProgress] = [:]
        for recurring in schedules {
            let id = recurring.persistentModelID
            startingAmounts[id] = recurring.currentStartingAmount()
            progress[id] = recurring.purchaseProgress
        }
        self.startingAmounts = startingAmounts
        self.progress = progress
    }

    /// What `recurring`'s transactions start at now (``RecurringTransaction/currentStartingAmount()``), read from the
    /// store only when it wasn't among the schedules the figures were worked out for.
    func startingAmount(of recurring: RecurringTransaction) -> Money {
        startingAmounts[recurring.persistentModelID] ?? recurring.currentStartingAmount()
    }

    /// `recurring`'s progress when it is a Purchase (``RecurringTransaction/purchaseProgress``), otherwise `nil`.
    func purchaseProgress(of recurring: RecurringTransaction) -> PurchaseProgress? {
        progress[recurring.persistentModelID]
    }
}
