import SwiftData
import SwiftUI

/// The With row of a form: the people chosen, or "None". Tapping it opens the ``WithMenu``. A Loan or Debt (`picksOne`)
/// is with one Person; anything else is with several (ADR-0009).
struct WithField: View {
    @Binding var people: [Person]
    let picksOne: Bool

    @State private var isChoosing = false

    var body: some View {
        Button {
            isChoosing = true
        } label: {
            LabeledContent("With") {
                Text(people.isEmpty ? String(localized: "None") : people.map(\.name).joined(separator: ", "))
                    .foregroundStyle(people.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $isChoosing) {
            WithMenu(people: $people, picksOne: picksOne)
        }
    }
}

/// What the With field opens: a search field and the Previous section, the people who aren't hidden with the one used
/// most lately first. Tapping a name chooses them; a Loan or Debt (`picksOne`) takes one Person and closes the menu,
/// anything else takes several, each tap choosing or un-choosing. When what was typed isn't the name of anyone in
/// Previous, "Add *Name*" makes that Person (or brings back a hidden one of that name), with an optional phone number.
/// Swiping a name offers Hide, which leaves them out of Previous and keeps their history. Below Previous, a Contacts
/// section lists the user's contacts matching what was typed, once they allow it; picking one links the Person to it
/// (``WithContactsSection``, ADR-0009).
struct WithMenu: View {
    @Binding var people: [Person]
    let picksOne: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(Person.previous) private var previous: [Person]
    @State private var query = ""
    @State private var phone = ""
    @State private var errorMessage: String?
    @State private var contacts = ContactsInWith()

    private func isChosen(_ person: Person) -> Bool {
        people.contains { $0 === person }
    }

    /// The chosen people Previous doesn't list, such as one hidden since: kept in view so they can be un-chosen.
    private var chosenElsewhere: [Person] {
        people.filter { person in !previous.contains { $0 === person } }
    }

    var body: some View {
        let listed = PreviousPeople(previous, typed: query)
        NavigationStack {
            List {
                if let name = listed.addableName {
                    Section {
                        Button {
                            add(name)
                        } label: {
                            Label("Add \(name)", systemImage: "plus.circle")
                        }
                        TextField("Phone (optional)", text: $phone)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                    }
                }
                if !chosenElsewhere.isEmpty {
                    Section("Chosen") {
                        ForEach(chosenElsewhere) { person in
                            row(person)
                        }
                    }
                }
                if !listed.people.isEmpty {
                    Section("Previous") {
                        ForEach(listed.people) { person in
                            row(person)
                                .swipeActions {
                                    Button("Hide", systemImage: "eye.slash") { hide(person) }
                                        .tint(.orange)
                                }
                        }
                    }
                }
                WithContactsSection(contacts: contacts, typed: query, pick: pick)
            }
            .searchable(text: $query, prompt: "Search or add a name")
            .overlay {
                if previous.isEmpty && chosenElsewhere.isEmpty && contacts.results.isEmpty && query.isEmpty {
                    ContentUnavailableView {
                        Label("No One Yet", systemImage: "person.2")
                    } description: {
                        Text("Search for a name to add the first person.")
                    }
                }
            }
            .navigationTitle("With")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .errorAlert("Couldn't Update People", message: $errorMessage)
            .task { await contacts.open(in: context) }
            .task(id: query) { await contacts.search(query) }
            .onReceive(ContactsInWith.changed) { _ in
                Task {
                    await contacts.refreshPeople(in: context)
                    await contacts.search(query)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 400)
        #endif
    }

    private func row(_ person: Person) -> some View {
        Button {
            choose(person)
        } label: {
            HStack {
                Text(person.name)
                Spacer(minLength: 8)
                if isChosen(person) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }

    private func choose(_ person: Person) {
        people.choose(person, picksOne: picksOne)
        if picksOne { dismiss() }
    }

    private func add(_ name: String) {
        do {
            finishAdding(try Person.add(named: name, phone: phone, in: context))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Picking a contact: `phone` is the number the user chose when the contact has several.
    private func pick(_ contact: Contact, phone: String?) {
        do {
            finishAdding(try Person.add(contact, phone: phone, in: context))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Chooses a Person just added or picked, and clears what was typed.
    private func finishAdding(_ person: Person) {
        if !isChosen(person) {
            people.choose(person, picksOne: picksOne)
        }
        query = ""
        phone = ""
        if picksOne { dismiss() }
    }

    private func hide(_ person: Person) {
        do {
            try person.hide()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
