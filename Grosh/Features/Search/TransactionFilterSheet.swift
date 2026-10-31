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
                    AmountBoundField(title: Strings.Search.atLeast, amount: $filter.minimumAmount)
                    AmountBoundField(title: Strings.Search.atMost, amount: $filter.maximumAmount)
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

/// One end of the amount range, typed as a plain amount such as `50` or `12.50`. Empty means any.
private struct AmountBoundField: View {
    let title: LocalizedStringResource
    @Binding var amount: Money?

    @State private var text: String

    init(title: LocalizedStringResource, amount: Binding<Money?>) {
        self.title = title
        _amount = amount
        _text = State(initialValue: amount.wrappedValue.map(Self.text(for:)) ?? "")
    }

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(Strings.Common.any))
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
