import Foundation
import SwiftData

extension Transaction {
    /// Puts `chosen` in With, each once, and keeps ``withName`` in step. Every one of them was last used at `date`.
    /// Doesn't save. The one-Person rule of a Loan or Debt is the draft's to check
    /// (``TransactionRuleError/tooManyWith``).
    func setPeople(_ chosen: [Person], usedAt date: Date = .now) {
        var unique: [Person] = []
        for person in chosen where !unique.contains(where: { $0 === person }) {
            unique.append(person)
        }
        people = unique
        refreshWithName()
        for person in unique {
            person.markUsed(at: date)
        }
    }
}

extension Person {
    /// Turns the With names typed before there were people into people (ADR-0009): one Person for each distinct name,
    /// ignoring case, spelled as the newest transaction with it spells it and last used when that transaction was
    /// entered. Every transaction, those in Recently Deleted too, keeps its With. Saves.
    ///
    /// Done once, when the store opens: it does nothing as soon as the store has any Person, since every name has been
    /// turned into one by then, and a transaction with a name and no Person can't be made since.
    static func migrateWithNames(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Person>()) == 0 else { return }
        let named = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.withName != "" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        guard !named.isEmpty else { return }
        var people = PeopleByName()
        for transaction in named {
            let person = people.reuseOrCreate(transaction.withName, lastUsedAt: transaction.createdAt, in: context)
            transaction.setPeople(person.map { [$0] } ?? [], usedAt: transaction.createdAt)
        }
        try context.save()
    }
}
