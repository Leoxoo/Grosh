import SwiftData
import SwiftUI

/// What tapping a Card opens: the transactions paid with it one period at a time, and their total, to check against
/// the card's statement. A Credit card with a statement date shows its statement periods, any other Card calendar
/// months. It opens on the current period; ‹ › step back through the periods with the Card's transactions and forward
/// again. A statement period also lists its lead-in transactions, muted under "Previous statement": each can be added
/// to the statement total for as long as this screen shows that statement, and nothing about it is saved. Use inside a
/// `NavigationStack`.
struct CardTransactionsView: View {
    let card: Card

    @Environment(\.today) private var today
    /// How many periods before the current one is showing: 0 for the current period, negative for a later one holding
    /// a transaction dated after today.
    @State private var periodsBack = 0
    @State private var isEditing = false
    /// The lead-in transactions the user added to the statement total for now. Cleared on stepping to another period.
    @State private var addedLeadIns = Set<Transaction>()

    /// Whether the Card was merged into another or deleted, from its editor, while this screen was open.
    private var isRemoved: Bool { card.isDeleted || card.modelContext == nil }

    var body: some View {
        Group {
            if isRemoved {
                ContentUnavailableView(
                    Strings.Cards.cardRemoved,
                    systemImage: Card.symbolName,
                    description: Text(Strings.Cards.cardRemovedDescription)
                )
            } else {
                periodList
            }
        }
        .navigationTitle(isRemoved ? "" : card.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isEditing) {
            CardEditor(mode: .edit(card))
        }
        .onChange(of: periodsBack) {
            addedLeadIns = []
        }
    }

    /// The period being shown, its count and total, then its transactions by day and its lead-in transactions.
    private var periodList: some View {
        let period = card.period(containing: today).adding(-periodsBack)
        let shown = card.transactions(in: period)
        let leadIns = card.leadInTransactions(in: period)
        let added = leadIns.filter { addedLeadIns.contains($0) }

        return List {
            Section {
                CardPeriodStepper(
                    period: period, periods: card.periods(today: today), today: today, periodsBack: $periodsBack
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
                        Text(Strings.Cards.includesFromPreviousStatement(added.count))
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

            if !leadIns.isEmpty {
                Section {
                    ForEach(leadIns.inListOrder()) { transaction in
                        LeadInTransactionRow(
                            transaction: transaction, isAdded: addedLeadIns.contains(transaction)
                        ) {
                            if addedLeadIns.remove(transaction) == nil {
                                addedLeadIns.insert(transaction)
                            }
                        }
                    }
                } header: {
                    Text(Strings.Cards.previousStatementSection)
                } footer: {
                    Text(Strings.Cards.previousStatementFooter(CardPeriod.leadInDayCount))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.Common.edit) { isEditing = true }
            }
        }
    }
}

/// A lead-in transaction: muted, since it belongs to the previous statement, but opening its detail like any other,
/// with a + that adds it to the statement total for now, or takes it back out once added.
private struct LeadInTransactionRow: View {
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
    }
}
