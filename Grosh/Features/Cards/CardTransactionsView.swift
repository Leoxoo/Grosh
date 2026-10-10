import SwiftData
import SwiftUI

/// What tapping a Card opens: the transactions paid with it one period at a time, and their total, to check against
/// the card's statement. A Credit card with a statement date shows its statement periods, any other Card calendar
/// months. It opens on the current period; ‹ › step back through the periods with the Card's transactions and forward
/// again. Use inside a `NavigationStack`.
struct CardTransactionsView: View {
    let card: Card

    /// How many periods before the current one is showing: 0 for the current period, negative for a later one holding
    /// a transaction dated after today.
    @State private var periodsBack = 0
    @State private var isEditing = false

    /// Whether the Card was merged into another or deleted, from its editor, while this screen was open.
    private var isRemoved: Bool { card.isDeleted || card.modelContext == nil }

    var body: some View {
        Group {
            if isRemoved {
                ContentUnavailableView(
                    "Card Removed",
                    systemImage: Card.symbolName,
                    description: Text("It was merged into another Card or deleted.")
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
    }

    /// The period being shown, its count and total, then its transactions by day.
    private var periodList: some View {
        let today = CalendarDay.today
        let period = card.period(containing: today).adding(-periodsBack)
        let shown = card.transactions(in: period)

        return List {
            Section {
                CardPeriodStepper(
                    period: period, periods: card.periods(today: today), today: today, periodsBack: $periodsBack
                )
                LabeledContent("Transactions") {
                    Text(shown.count.formatted())
                        .monospacedDigit()
                }
                LabeledContent(period.isStatement ? "Statement total" : "Total") {
                    AmountText(amount: shown.net, showsPlusSign: true)
                        .fontWeight(.semibold)
                }
            } footer: {
                if period.isStatement {
                    Text("A statement period runs from the day after one statement date through the next.")
                } else if card.kind == .credit {
                    Text("Add the day this card's statement closes to see its transactions by statement period.")
                }
            }

            if shown.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: Card.symbolName,
                        description: Text("Nothing was paid with this Card in this period.")
                    )
                }
            }

            TransactionDaySections(transactions: shown) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
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
            .accessibilityLabel(period.isStatement ? "Previous Statement" : "Previous Month")
            .disabled(period <= periods.lowerBound)

            Spacer()
            VStack(spacing: 2) {
                Text(period.title(today: today, locale: locale))
                    .font(.headline)
                    .monospacedDigit()
                if period.isStatement {
                    Text(period.contains(today) ? "Current statement" : "Statement period")
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
            .accessibilityLabel(period.isStatement ? "Next Statement" : "Next Month")
            .disabled(period >= periods.upperBound)
        }
        .buttonStyle(.borderless)
    }
}
