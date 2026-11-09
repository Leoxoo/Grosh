import Foundation
import SwiftData

/// Why a change to a model couldn't be saved.
nonisolated enum StoreError: Error, Equatable {
    /// The model isn't in the store any more: it was removed for good, or never added. A change to it would be lost.
    case notInStore
}

extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notInStore: String(localized: Strings.Common.notInStore)
        }
    }
}

nonisolated extension PersistentModel {
    /// The context holding the model, for a rule that changes the store through it. A model the store no longer holds
    /// has none (SwiftData clears it once the model is removed for good), and a change to it would silently go
    /// nowhere, so this throws ``StoreError/notInStore`` instead and the change is refused out loud.
    func storeContext() throws -> ModelContext {
        guard let modelContext else { throw StoreError.notInStore }
        return modelContext
    }

    /// Saves the context holding the model, or throws ``StoreError/notInStore`` when the store no longer holds it.
    func saveToStore() throws {
        try storeContext().save()
    }
}
