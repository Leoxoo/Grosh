import SwiftData
import SwiftUI

/// The transaction detail's Owes me for an Expense: each Person yet to pay part of it back, opening its own detail, and
/// the money paid back into other wallets, opening that transaction (ADR-0010). Shows nothing for a transaction with
/// neither. Use inside a `List`.
struct OwesMeSection: View {
    let transaction: Transaction
    @Environment(\.today) private var today

    var body: some View {
        let expectations = transaction.orderedExpectations
        if !expectations.isEmpty {
            Section {
                ForEach(expectations) { expectation in
                    NavigationLink {
                        ExpectedReimbursementDetailView(expectation: expectation)
                    } label: {
                        ExpectedReimbursementRow(expectation: expectation, today: today)
                    }
                }
            } header: {
                Text(Strings.OwesMe.owesMe)
            } footer: {
                Text(Strings.OwesMe.sectionFooter)
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
                                Text(payback.day.shortText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(Strings.OwesMe.paidBackIntoOtherWallets)
            } footer: {
                Text(Strings.OwesMe.otherWalletsFooter)
            }
        }
    }
}
