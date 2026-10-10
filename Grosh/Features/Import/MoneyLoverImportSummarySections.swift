import SwiftUI

/// What an import from MoneyLover did, as list sections: how many rows went into each wallet, how many Cards were
/// created, and the rows that couldn't be matched. Use inside a `List`.
struct MoneyLoverImportSummarySections: View {
    let summary: MoneyLoverImportSummary

    var body: some View {
        Section {
            LabeledContent("Transactions", value: summary.transactionCount.formatted())
            LabeledContent("Cards created", value: summary.cardsCreated.formatted())
        } header: {
            Text("Imported")
        }

        Section("Wallets") {
            ForEach(summary.wallets, id: \.name) { wallet in
                LabeledContent(wallet.name, value: wallet.transactionCount.formatted())
            }
        }

        Section {
            if summary.unmatchedRows.isEmpty {
                Text("Every transfer and payment was matched.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.unmatchedRows, id: \.row.line) { unmatched in
                    UnmatchedRowView(unmatched: unmatched)
                }
            }
        } header: {
            Text("Unmatched rows")
        }
    }
}

/// One row the import couldn't match: where it is in the file, what it was, and what became of it.
private struct UnmatchedRowView: View {
    let unmatched: MoneyLoverImportSummary.UnmatchedRow
    private var row: MoneyLoverRow { unmatched.row }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.categoryName)
                Text("Line \(row.line) · \(row.day.date().formatted(date: .numeric, time: .omitted)) · \(row.walletName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(unmatched.outcome.wording)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: row.amount)
        }
    }
}

private extension MoneyLoverImportSummary.UnmatchedRow.Outcome {
    var wording: String {
        switch self {
        case .balanceAdjustment: String(localized: "No partner: recorded as a balance adjustment")
        case .notImported: String(localized: "No partner and no amount: not imported")
        case .unlinkedPayment: String(localized: "No open Loan or Debt of this amount: not linked")
        }
    }
}

#Preview {
    List {
        MoneyLoverImportSummarySections(summary: MoneyLoverImportSummary(
            wallets: [.init(name: "Checking", transactionCount: 1_204), .init(name: "Cash", transactionCount: 312)],
            cardsCreated: 4,
            unmatchedRows: [
                .init(
                    row: MoneyLoverRow(
                        line: 18, day: CalendarDay(year: 2026, month: 9, day: 2), categoryName: "Incoming transfer",
                        amount: Money(cents: 120_00), walletName: "Cash", note: "", withName: "", eventName: "",
                        isExcludedFromReport: true
                    ),
                    outcome: .balanceAdjustment
                ),
            ]
        ))
    }
}
