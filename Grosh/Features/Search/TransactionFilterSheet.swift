import SwiftData
import SwiftUI

/// The filters a transaction list can be narrowed by: wallet, category, Card, With, type, date range, amount range and
/// excluded only. Every wallet, category, Card and Person is offered, archived and hidden ones included, since their
/// history stays searchable; choosing a parent category includes its subcategories. Changes apply as they are made;
/// Clear resets every filter but leaves the search text.
struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WalletPicker(title: "Wallet", everyWalletOr: "Any", selection: $filter.wallet)
                    CategoryPicker(title: "Category", everyCategoryOr: "Any", selection: $filter.category)
                    CardPicker(title: "Card", everyCardOr: "Any", selection: $filter.card)
                    WithFilterPicker(selection: $filter.person)
                    Picker("Type", selection: $filter.type) {
                        Text("Any").tag(CategoryType?.none)
                        ForEach(CategoryType.segments, id: \.self) { type in
                            Text(type.title).tag(Optional(type))
                        }
                    }
                } footer: {
                    if filter.card != nil {
                        Text("The list's header shows the Card's total for the period.")
                    }
                }

                Section("Date Range") {
                    OptionalDayRow(title: "From", day: $filter.dateRange.first)
                    OptionalDayRow(title: "To", day: $filter.dateRange.last)
                }

                Section {
                    AmountBoundField(title: "At least", amount: $filter.minimumAmount)
                    AmountBoundField(title: "At most", amount: $filter.maximumAmount)
                } header: {
                    Text("Amount Range")
                } footer: {
                    Text("Amounts as entered, whether money went in or out.")
                }

                Section {
                    Toggle("Excluded from report only", isOn: $filter.excludedOnly)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { filter.clearFilters() }
                        .disabled(!filter.hasFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
    let title: LocalizedStringKey
    @Binding var day: CalendarDay?

    var body: some View {
        Toggle(title, isOn: Binding(get: { day != nil }, set: { day = $0 ? .today : nil }))
        if let day = Binding($day) {
            DayPicker(title: title, day: day)
                .labelsHidden()
        }
    }
}

/// One end of the amount range, typed as a plain amount such as `50` or `12.50`. Empty means any.
private struct AmountBoundField: View {
    let title: LocalizedStringKey
    @Binding var amount: Money?

    @State private var text: String

    init(title: LocalizedStringKey, amount: Binding<Money?>) {
        self.title = title
        _amount = amount
        _text = State(initialValue: amount.wrappedValue.map(Self.text(for:)) ?? "")
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text("Any"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
        .onChange(of: text) {
            amount = Self.amount(in: text)
        }
        .onChange(of: amount) {
            // Clear empties the field.
            if Self.amount(in: text) != amount {
                text = amount.map(Self.text(for:)) ?? ""
            }
        }
    }

    private static func amount(in text: String) -> Money? {
        Money(typedAmount: text).map { Money(cents: abs($0.cents)) }
    }

    nonisolated private static func text(for amount: Money) -> String {
        amount.decimalValue.formatted(.number.grouping(.never))
    }
}
