import Foundation
import SwiftData

extension Transaction {
    /// The With names used before that contain `text` (ignoring case and accents), most recently used first,
    /// each name once, for the With field to autocomplete. A name typed in full isn't suggested back.
    static func withNames(matching text: String, limit: Int = 5, in context: ModelContext) throws -> [String] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.withName != "" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        var seen = Set<String>()
        var names: [String] = []
        for name in try context.fetch(descriptor).map(\.withName) {
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard seen.insert(key).inserted else { continue }
            guard typed.isEmpty || name.localizedStandardContains(typed) else { continue }
            guard name.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame else { continue }
            names.append(name)
            if names.count == limit { break }
        }
        return names
    }
}
