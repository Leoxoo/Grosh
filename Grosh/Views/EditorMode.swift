import SwiftData

/// Whether an editor sheet adds a new `Model` or edits one. A list presents the editor with `.sheet(item:)`.
enum EditorMode<Model: PersistentModel>: Identifiable {
    case add
    case edit(Model)

    var id: AnyHashable {
        switch self {
        case .add: "add"
        case .edit(let model): model.persistentModelID
        }
    }

    /// The model being edited, or `nil` when adding.
    var editing: Model? {
        if case .edit(let model) = self { model } else { nil }
    }

    var isAdding: Bool { editing == nil }
}
