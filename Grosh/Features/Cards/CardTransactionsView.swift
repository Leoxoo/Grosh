import SwiftData
import SwiftUI

/// What tapping a Card opens: what it earns (``CardRewardsSection``), then the transactions paid with it one period at
/// a time, and their total, to check against the card's statement. A Credit card with a statement date shows its
/// statement periods, any other Card calendar months. It opens on the current period; ‹ › step back through the periods
/// with the Card's transactions and forward again. A statement period also lists its nearby transactions, from the days
/// just before and after it, muted under "Around this statement": each can be added to the statement total for as long
/// as this screen shows that statement, and nothing about it is saved. Use inside a `NavigationStack`.
struct CardTransactionsView: View {
    let card: Card

    @Environment(\.today) private var today
    /// How many periods before the current one is showing: 0 for the current period, negative for a later one holding
    /// a transaction dated after today.
    @State private var periodsBack = 0
    @State private var isEditing = false
    /// The nearby transactions the user added to the statement total for now. Cleared on stepping to another period.
    @State private var addedNearby = Set<Transaction>()

    var body: some View {
        // The Card can be merged into another or deleted, from its editor, while this screen is open.
        Group {
            if card.isGone {
                ContentUnavailableView(
                    Strings.Cards.cardRemoved,
                    systemImage: Card.symbolName,
                    description: Text(Strings.Cards.cardRemovedDescription)
                )
            } else {
                let period = card.period(containing: today).adding(-periodsBack)
                CardPeriodList(
                    card: card, period: period, today: today, periodsBack: $periodsBack, addedNearby: $addedNearby
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(Strings.Common.edit) { isEditing = true }
                    }
                }
            }
        }
        .navigationTitle(card.isGone ? "" : card.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isEditing) {
            CardEditor(mode: .edit(card))
        }
        .onChange(of: periodsBack) {
            addedNearby = []
        }
    }
}

/// The period being shown, its count and total, then its transactions by day and its nearby transactions. The Card's
/// transactions on the period's days, and its first and last, are read by the store for the period shown, rather than by
/// walking every transaction the Card paid for on each draw.
private struct CardPeriodList: View {
    let card: Card
    let period: CardPeriod
    let today: CalendarDay
    @Binding var periodsBack: Int
    /// The nearby transactions the user added to the statement total for now.
    @Binding var addedNearby: Set<Transaction>

    @Query private var paid: [Transaction]
    @Query private var earliest: [Transaction]
    @Query private var latest: [Transaction]
    /// What the Rewards section has open, presented from the list rather than from inside it.
    @State private var rewardsAction: CardRewardsAction?
    @State private var errorMessage: String?

    init(
        card: Card, period: CardPeriod, today: CalendarDay, periodsBack: Binding<Int>,
        addedNearby: Binding<Set<Transaction>>
    ) {
        self.card = card
        self.period = period
        self.today = today
        _periodsBack = periodsBack
        _addedNearby = addedNearby
        let reads = CardStatement.Reads(card: card, for: period)
        _paid = Query(reads.paid)
        _earliest = Query(reads.earliest)
        _latest = Query(reads.latest)
    }

    var body: some View {
        let statement = CardStatement(
            of: card, for: period, paid: paid, earliest: earliest, latest: latest, today: today
        )
        let shown = statement.transactions
        let nearby = statement.nearby
        let added = nearby.filter { addedNearby.contains($0) }

        List {
            CardRewardsSection(card: card, today: today, action: $rewardsAction)

            Section {
                CardPeriodStepper(
                    period: period, periods: statement.periods, today: today, periodsBack: $periodsBack
                )
                LabeledContent(Strings.Common.transactions) {
                    Text(shown.count.formatted())
                        .monospacedDigit()
                }
                LabeledContent {
                    AmountText(amount: (shown + added).charged, showsPlusSign: true, showsColor: false)
                        .fontWeight(.semibold)
                } label: {
                    Text(period.isStatement ? Strings.Cards.statementTotal : Strings.Common.total)
                    if !added.isEmpty {
                        Text(Strings.Cards.includesFromAroundStatement(added.count))
                    }
                }
            } footer: {
                if period.isStatement {
                    Text(Strings.Cards.statementPeriodFooter)
                } else if card.kind == .credit {
                    Text(Strings.Cards.addStatementDayFooter)
                }
            }

            if shown.isEmpty {
                Section {
                    ContentUnavailableView(
                        Strings.Common.noTransactions,
                        systemImage: Card.symbolName,
                        description: Text(Strings.Cards.nothingPaidInPeriod)
                    )
                }
            }

            // A statement shows what the Card was charged, Reimbursements not counted, so it reconciles with the Card.
            TransactionDaySections(transactions: shown, listed: .charged) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction, listed: .charged)
                }
            }

            if !nearby.isEmpty {
                Section {
                    ForEach(nearby.inListOrder()) { transaction in
                        NearbyTransactionRow(
                            transaction: transaction, isAdded: addedNearby.contains(transaction)
                        ) {
                            if addedNearby.remove(transaction) == nil {
                                addedNearby.insert(transaction)
                            }
                        }
                    }
                } header: {
                    Text(Strings.Cards.nearbySection)
                } footer: {
                    Text(Strings.Cards.nearbyFooter(CardPeriod.nearbyDayCount))
                }
            }
        }
        .sheet(item: $rewardsAction) { action in
            action.sheet(for: card, errorMessage: $errorMessage)
        }
        .errorAlert(Strings.Cards.couldntChange, message: $errorMessage)
    }
}

/// A nearby transaction: muted, since it belongs to the previous or the next statement, but opening its detail like any
/// other, with a + that adds it to the statement total for now, or takes it back out once added.
private struct NearbyTransactionRow: View {
    let transaction: Transaction
    let isAdded: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .imageScale(.large)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isAdded ? Strings.Cards.removeFromStatementTotal : Strings.Cards.addToStatementTotal)

            NavigationLink {
                TransactionDetailView(transaction: transaction)
            } label: {
                TransactionRow(transaction: transaction, showsDay: true, listed: .charged)
                    .opacity(0.55)
            }
        }
    }
}

/// The period being shown between ‹ and ›, which step one period back or forward within `periods`.
private struct CardPeriodStepper: View {
    let period: CardPeriod
    /// The periods there is something to show in, oldest first.
    let periods: ClosedRange<CardPeriod>
    let today: CalendarDay
    @Binding var periodsBack: Int

    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            Button {
                periodsBack += 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .accessibilityLabel(period.isStatement ? Strings.Cards.previousStatement : Strings.Cards.previousMonth)
            .disabled(period <= periods.lowerBound)

            Spacer()
            VStack(spacing: 2) {
                Text(period.title(today: today, locale: locale))
                    .font(.headline)
                    .monospacedDigit()
                if period.isStatement {
                    Text(period.contains(today) ? Strings.Cards.currentStatement : Strings.Cards.statementPeriod)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()

            Button {
                periodsBack -= 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 28, minHeight: 28)
            }
            .accessibilityLabel(period.isStatement ? Strings.Cards.nextStatement : Strings.Cards.nextMonth)
            .disabled(period >= periods.upperBound)
        }
        .buttonStyle(.borderless)
        // The list starts a row's separator under its first text, here the centered title; start it at the row's
        // leading edge, as under the other rows.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}
