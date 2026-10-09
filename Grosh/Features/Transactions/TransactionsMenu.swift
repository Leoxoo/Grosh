import SwiftUI

/// The Transactions tab's "…" menu: making a Transfer or adjusting a balance, and choosing how the list is shown.
struct TransactionsMenu: View {
    /// The wallet the tab is showing, for actions that start from it.
    let walletSelection: WalletSelection
    @Binding var timeRange: TimeRange

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Section {
                Button("Transfer", systemImage: "arrow.left.arrow.right") {}
                    .disabled(true)
            }

            Section {
                Button("Adjust Balance", systemImage: "plusminus") {}
                    .disabled(true)
            }

            Section {
                Picker("Time Range", systemImage: "calendar", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Button("View by Category", systemImage: "square.grid.2x2") {}
                    .disabled(true)
                Button("Select Multiple", systemImage: "checkmark.circle") {}
                    .disabled(true)
            }
        }
    }
}

extension TimeRange {
    var title: String {
        switch self {
        case .month: String(localized: "Month")
        }
    }
}
