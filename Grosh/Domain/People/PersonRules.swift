import Foundation
import SwiftData

/// Why a Person can't be added.
nonisolated enum PersonRuleError: Error, Equatable {
    /// A Person needs a name.
    case missingName
}

extension PersonRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "Enter a name.")
        }
    }
}

nonisolated extension String {
    /// The text trimmed, or `nil` when it holds nothing: a phone number or name typed into an optional field.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated extension Sequence {
    /// The elements whose `name` contains what was typed (ignoring case and accents), in the order given, or all of them
    /// while nothing is typed: how the With menu searches its Previous section and Contacts alike.
    func filter(nameContaining typed: String, name: (Element) -> String) -> [Element] {
        guard let query = typed.nilIfBlank else { return Array(self) }
        return filter { name($0).localizedStandardContains(query) }
    }
}

extension Person {
    /// What two names are compared by: trimmed, ignoring case. Two people never share it (ADR-0009).
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Adds the Person called `name`, or reuses the one that already has it (ignoring case), and chooses them: their
    /// last-used date moves to now, and a hidden Person comes back to Previous. A new Person keeps `phone` when it
    /// holds something; an existing one keeps what they have. Saves. Throws ``PersonRuleError/missingName`` for a name
    /// of nothing but spaces.
    ///
    /// This is what typing a name in With, or Add *Name* in the With menu, does.
    @discardableResult
    static func add(named name: String, phone: String? = nil, in context: ModelContext) throws -> Person {
        var people = PeopleByName(try context.fetch(FetchDescriptor<Person>()))
        guard let person = people.reuseOrCreate(name, phone: phone, in: context) else {
            throw PersonRuleError.missingName
        }
        person.isHidden = false
        person.markUsed()
        try context.save()
        return person
    }

    /// Records that the Person was chosen at `date`. A Person is never made less recent: choosing them on an old
    /// transaction, as the import does, leaves a later use alone.
    func markUsed(at date: Date = .now) {
        lastUsedAt = max(lastUsedAt, date)
    }

    /// Hide: leaves the Person out of Previous. Their name and their place on every transaction stay; typing their name
    /// again brings them back (``add(named:phone:in:)``). Saves.
    func hide() throws {
        isHidden = true
        try modelContext?.save()
    }

    /// Everyone who isn't hidden, the one used most lately first and equal dates by name: what the With menu's Previous
    /// section lists (``PreviousPeople``).
    static var previous: FetchDescriptor<Person> {
        FetchDescriptor(
            predicate: #Predicate { !$0.isHidden },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse), SortDescriptor(\.name)]
        )
    }

    /// Every Person, hidden ones included, by name: for a filter, whose history includes the people since hidden.
    static var everyone: FetchDescriptor<Person> {
        FetchDescriptor(sortBy: [SortDescriptor(\.name)])
    }
}

/// The people in the store found by name (ignoring case), for code that looks many up or adds many, such as the
/// With names migration and the import: a name is found in a dictionary rather than by fetching again. The caller reads
/// the people from the store once and passes them in.
struct PeopleByName {
    private var byKey: [String: Person]

    /// No one yet, for code that adds every Person it needs.
    init() {
        byKey = [:]
    }

    init(_ people: some Sequence<Person>) {
        byKey = Dictionary(people.map { (Person.key($0.name), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The Person called `name`, or `nil` when there is none.
    func person(named name: String) -> Person? {
        byKey[Person.key(name)]
    }

    /// The Person called `name` (trimmed), made and inserted into `context` when there is none: with `phone` when it
    /// holds something, last used at `lastUsedAt`. `nil` for a name of nothing but spaces. Doesn't save, and leaves an
    /// existing Person as they are, hidden or not.
    mutating func reuseOrCreate(
        _ name: String, phone: String? = nil, lastUsedAt: Date = .now, in context: ModelContext
    ) -> Person? {
        guard let trimmed = name.nilIfBlank else { return nil }
        if let existing = person(named: trimmed) { return existing }
        let person = Person(name: trimmed, phone: phone?.nilIfBlank, lastUsedAt: lastUsedAt)
        context.insert(person)
        byKey[Person.key(trimmed)] = person
        return person
    }
}

/// What the With menu lists for the text typed in its search field: the Previous section, and the name "Add" offers.
struct PreviousPeople {
    /// The Previous section: the people who aren't hidden whose names contain what was typed (ignoring case and
    /// accents), in the order given, or all of them while nothing is typed.
    let people: [Person]
    /// The name "Add *Name*" offers, or `nil` while nothing is typed or someone who isn't hidden already has exactly
    /// that name. A hidden Person with that name is brought back by adding it.
    let addableName: String?

    /// `previous`, the people who aren't hidden most recently used first (``Person/previous``), narrowed by `typed`.
    init(_ previous: [Person], typed: String) {
        people = previous.filter(nameContaining: typed, name: \.name)
        let query = typed.nilIfBlank
        let key = query.map(Person.key)
        addableName = previous.contains(where: { Person.key($0.name) == key }) ? nil : query
    }
}

extension Array where Element == Person {
    /// Chooses `person` in the With menu. A Loan or Debt (`picksOne`) is with exactly one Person, so they replace whoever
    /// was chosen; anything else is with several, so choosing a Person who is chosen already takes them out again.
    mutating func choose(_ person: Person, picksOne: Bool) {
        if picksOne {
            self = [person]
        } else if let index = firstIndex(where: { $0 === person }) {
            remove(at: index)
        } else {
            append(person)
        }
    }
}
