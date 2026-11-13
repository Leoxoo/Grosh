import Foundation
import SwiftData
import SwiftUI

/// How many times the view's model context has saved the store since the view first read it. A view reading it draws
/// again after each save, and a value it keeps in a ``DrawingCache`` under the count is worked out once per save, such
/// as a varying Bill's estimate (``RecurringSchedules``), which any saved transaction can change. The editors save
/// through the same context, so their saves are counted too.
@propertyWrapper
struct StoreSaves: DynamicProperty {
    @Environment(\.modelContext) private var context
    @State private var counter = Counter()

    var wrappedValue: Int { counter.count(of: context) }

    @Observable
    final class Counter {
        private var count = 0
        @ObservationIgnored private weak var context: ModelContext?
        @ObservationIgnored nonisolated(unsafe) private var saves: (any NSObjectProtocol)?

        /// The saves of `context` counted so far, counting from now on when it isn't the context already counted.
        func count(of context: ModelContext) -> Int {
            if self.context !== context {
                if let saves { NotificationCenter.default.removeObserver(saves) }
                self.context = context
                saves = NotificationCenter.default.addObserver(
                    forName: ModelContext.didSave, object: context, queue: nil
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.count += 1 }
                }
            }
            return count
        }

        deinit {
            if let saves { NotificationCenter.default.removeObserver(saves) }
        }
    }
}

/// The models a value was worked out from and the saves counted then (``StoreSaves``): a ``DrawingCache`` key, so the
/// value is worked out again when the models change or the store is saved.
struct AsSaved: Equatable {
    private let models: [PersistentIdentifier]
    private let saves: Int

    init(_ models: [some PersistentModel], saves: Int) {
        self.models = models.map(\.persistentModelID)
        self.saves = saves
    }
}
