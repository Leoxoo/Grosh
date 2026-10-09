import SwiftUI

/// The transaction detail's "recorded → actual" for a balance adjustment: its wallet's balance just before it and
/// just after. Shows nothing for any other transaction. Use inside a `List`.
struct BalanceChangeSection: View {
    let transaction: Transaction

    var body: some View {
        if let change = transaction.balanceChange {
            Section {
                LabeledContent("Balance") {
                    HStack(spacing: 6) {
                        Text(change.recorded.formatted())
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("to")
                        Text(change.actual.formatted())
                    }
                    .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Balance adjustment")
            } footer: {
                Text("What the wallet's transactions added up to, and its actual balance after this adjustment.")
            }
        }
    }
}
