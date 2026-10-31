import SwiftData
import SwiftUI

/// The filters a transaction list can be narrowed by: wallet, category, Card, With, type, date range, amount range and
/// excluded only. Every wallet, category, Card and Person is offered, archived and hidden ones included, since their
/// history stays searchable; choosing a parent category includes its subcategories. Changes apply as they are made;
/// Clear resets every filter but leaves the search text.
struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter

    @Environment(\.dismiss) private var dismiss
    @State private var keypad = KeypadTarget()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WalletPicker(title: Strings.Common.wallet, everyWalletOr: Strings.Common.any, selection: $filter.wallet)
                    CategoryPicker(title: Strings.Common.category, everyCategoryOr: Strings.Common.any, selection: $filter.category)
                    CardPicker(title: Strings.Common.card, everyCardOr: Strings.Common.any, selection: $filter.card)
                    WithFilterPicker(selection: $filter.person)
                    Picker(Strings.Common.type, selection: $filter.type) {
                        Text(Strings.Common.any).tag(CategoryType?.none)
                        ForEach(CategoryType.segments, id: \.self) { type in
                            Text(type.title).tag(Optional(type))
                        }
                    }
                } footer: {
                    if filter.card != nil {
                        Text(Strings.Search.cardTotalFooter)
                    }
                }

                Section(Strings.Search.dateRange) {
                    OptionalDayRow(title: Strings.Common.from, day: $filter.dateRange.first)
                    OptionalDayRow(title: Strings.Common.to, day: $filter.dateRange.last)
                }

                Section {
                    AmountBoundField(title: Strings.Search.atLeast, field: "minimum", amount: $filter.minimumAmount)
                    AmountBoundField(title: Strings.Search.atMost, field: "maximum", amount: $filter.maximumAmount)
                } header: {
                    Text(Strings.Search.amountRange)
                } footer: {
                    Text(Strings.Search.amountRangeFooter)
                }

                Section {
                    Toggle(Strings.Search.excludedOnly, isOn: $filter.excludedOnly)
                }
            }
            .formStyle(.grouped)
            .keypad(keypad)
            .navigationTitle(Strings.Screens.filters)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.clear) { filter.clearFilters() }
                        .disabled(!filter.hasFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.done) { dismiss() }
                }
            }
        }
    }
}

/// Picks the Person to narrow the list to: any of the people in a transaction's With counts. Every Person is offered,
/// hidden ones included, or Anyone.
private struct WithFilterPicker: View {
    @Binding var selection: Person?

    @Query(Person.everyone) private var everyone: [Person]

    var body: some View {
        Picker("With", selection: $selection) {
            Text("Anyone").tag(Person?.none)
            ForEach(everyone) { person in
                Text(person.isHidden ? "\(person.name) (Hidden)" : person.name)
                    .tag(Optional(person))
            }
        }
    }
}

/// One end of the date range: off leaves that side open.
private struct OptionalDayRow: View {
    let title: LocalizedStringResource
    @Binding var day: CalendarDay?

    @Environment(\.today) private var today

    var body: some View {
        Toggle(title, isOn: Binding(get: { day != nil }, set: { day = $0 ? today : nil }))
        if let day = Binding($day) {
            DayPicker(title: title, day: day)
                .labelsHidden()
        }
    }
}

/// One end of the amount range, typed on the Keypad. Empty, until a digit is typed and again after C, means any.
private struct AmountBoundField: View {
    let title: LocalizedStringResource
    let field: String
    @Binding var amount: Money?

    @State private var entry: AmountEntry

    init(title: LocalizedStringResource, field: String, amount: Binding<Money?>) {
        self.title = title
        self.field = field
        _amount = amount
        _entry = State(initialValue: Self.entry(for: amount.wrappedValue))
    }

    var body: some View {
        AmountRow(title, field: field, entry: $entry, placeholder: Strings.Common.any, font: .body)
            .onChange(of: entry) {
                amount = Self.amount(of: entry)
            }
            .onChange(of: amount) {
                // Clear empties the field.
                if Self.amount(of: entry) != amount {
                    entry = Self.entry(for: amount)
                }
            }
    }

    /// What was typed as a bound: nothing is any amount, and so is a calculation that can't be worked out.
    private static func amount(of entry: AmountEntry) -> Money? {
        guard !entry.isEmpty, let cents = entry.cents else { return nil }
        return Money(cents: cents)
    }

    /// `amount` on the Keypad, with a bound of zero shown as 0 rather than as any.
    private static func entry(for amount: Money?) -> AmountEntry {
        guard let amount else { return AmountEntry() }
        var entry = AmountEntry(cents: amount.cents)
        if amount.cents == 0 {
            entry.press(.digit(0))
        }
        return entry
    }
}
