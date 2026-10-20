import SwiftData
import SwiftUI

/// The transaction detail's Owes me for an Expense: each Person yet to pay part of it back, opening its own detail, and
/// the money paid back into other wallets, opening that transaction (ADR-0010). Shows nothing for a transaction with
/// neither. Use inside a `List`.
struct OwesMeSection: View {
    let transaction: Transaction

    var body: some View {
        let expectations = transaction.orderedExpectations
        if !expectations.isEmpty {
            Section {
                ForEach(expectations) { expectation in
                    NavigationLink {
                        ExpectedReimbursementDetailView(expectation: expectation)
                    } label: {
                        ExpectedReimbursementRow(expectation: expectation, today: .today)
                    }
                }
            } header: {
                Text("Owes Me")
            } footer: {
                Text("Owes me never changes a balance or a report. The expense stays at its full amount until money comes back.")
            }
        }
        let paybacks = transaction.paybacksElsewhere
        if !paybacks.isEmpty {
            Section {
                ForEach(paybacks) { payback in
                    NavigationLink {
                        TransactionDetailView(transaction: payback)
                    } label: {
                        LabeledContent {
                            AmountText(amount: payback.amount, showsPlusSign: true)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payback.wallet?.name ?? "")
                                Text(payback.day.date().formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Paid Back Into Other Wallets")
            } footer: {
                Text("Its own wallet keeps the full amount. The Total shows the expense net of these.")
            }
        }
    }
}
