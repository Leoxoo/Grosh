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
    @Query(Wallet.unarchived) private var wallets: [Wallet]

    /// The currency the amount range is shown in: the filtered wallet's, or the Total's
    /// (``WalletSelection/currencyCode(among:)``). The bounds themselves hold in each transaction's own currency.
    private var currencyCode: String {
        (filter.wallet.map(WalletSelection.wallet) ?? .total).currencyCode(among: wallets)
    }

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
                    AmountBoundField(
                        title: Strings.Search.atLeast, field: "minimum", cents: $filter.minimumCents,
                        currencyCode: currencyCode
                    )
                    AmountBoundField(
                        title: Strings.Search.atMost, field: "maximum", cents: $filter.maximumCents,
                        currencyCode: currencyCode
                    )
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
        Picker(Strings.Common.with, selection: $selection) {
            Text(Strings.People.anyone).tag(Person?.none)
            ForEach(everyone) { person in
                Text(person.isHidden ? String(localized: Strings.People.hiddenName(person.name)) : person.name)
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

/// One end of the amount range, typed on the Keypad. Empty, until a digit is typed and again after C, means any. The
/// filter holds only the bound in cents, so what is being typed (a calculation half done) is this field's own, kept in
/// step with the bound both ways.
private struct AmountBoundField: View {
    let title: LocalizedStringResource
    let field: String
    @Binding var cents: Int?
    /// The currency the bound is shown in.
    let currencyCode: String

    @State private var entry: AmountEntry

    init(title: LocalizedStringResource, field: String, cents: Binding<Int?>, currencyCode: String) {
        self.title = title
        self.currencyCode = currencyCode
        self.field = field
        _cents = cents
        _entry = State(initialValue: Self.entry(for: cents.wrappedValue))
    }

    var body: some View {
        AmountRow(title, field: field, entry: $entry, currencyCode: currencyCode, placeholder: Strings.Common.any, font: .body)
            .onChange(of: entry) {
                cents = Self.cents(of: entry)
            }
            .onChange(of: cents) {
                // Clear empties the field.
                if Self.cents(of: entry) != cents {
                    entry = Self.entry(for: cents)
                }
            }
    }

    /// What was typed as a bound: nothing is any amount, and so is a calculation that can't be worked out.
    private static func cents(of entry: AmountEntry) -> Int? {
        entry.isEmpty ? nil : entry.cents
    }

    /// `cents` on the Keypad, with a bound of zero shown as 0 rather than as any.
    private static func entry(for cents: Int?) -> AmountEntry {
        cents.map { AmountEntry(showing: $0) } ?? AmountEntry()
    }
}
