import SwiftUI

/// The Transactions tab's "…" menu: how the list shows its periods (time range, view by category), selecting
/// transactions to delete, and actions that start from the wallet the tab is showing.
struct TransactionsMenu: View {
    /// What the tab is showing: one wallet or the Total.
    let walletSelection: WalletSelection
    /// How long each period in the strip is.
    @Binding var timeRange: TimeRange
    /// Whether the list groups the period's transactions by day or by category.
    @Binding var grouping: TransactionGrouping
    /// Starts choosing transactions to delete.
    let startSelecting: () -> Void
    /// The list's search text and filters, which Filters sets on iPhone and iPad, where the bar has no room for a
    /// Filters button of its own beside the tab's title.
    @Binding var filter: TransactionFilter

    @State private var isPickingCustomRange = false
    @State private var isTransferring = false
    @State private var isAdjustingBalance = false
    @State private var isFiltering = false

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            #if os(iOS)
            Section {
                Button {
                    isFiltering = true
                } label: {
                    Label(
                        "Filters",
                        systemImage: filter.hasFilters
                            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                    )
                    if filter.hasFilters {
                        Text("On")
                    }
                }
            }
            #endif

            Section {
                Menu {
                    TimeRangeChoices(timeRange: $timeRange) { isPickingCustomRange = true }
                } label: {
                    Label("Time Range", systemImage: "calendar")
                    Text(timeRange.title)
                }

                Toggle("View by Category", systemImage: "square.grid.2x2", isOn: viewsByCategory)
            }

            Section {
                Button("Select", systemImage: "checkmark.circle", action: startSelecting)
            }

            Section {
                Button("Transfer", systemImage: "arrow.left.arrow.right") { isTransferring = true }
            }

            Section {
                Button("Adjust Balance", systemImage: "plusminus") { isAdjustingBalance = true }
            }
        }
        .customRangeEditor($timeRange, isPresented: $isPickingCustomRange)
        .sheet(isPresented: $isTransferring) {
            TransferEditor(viewedWallet: viewedWallet)
        }
        .sheet(isPresented: $isAdjustingBalance) {
            AdjustBalanceEditor(viewedWallet: viewedWallet)
        }
        .sheet(isPresented: $isFiltering) {
            TransactionFilterSheet(filter: $filter)
        }
    }

    private var viewsByCategory: Binding<Bool> {
        Binding(get: { grouping == .category }, set: { grouping = $0 ? .category : .day })
    }

    /// The one wallet the tab is showing, or `nil` for the Total.
    private var viewedWallet: Wallet? {
        if case .wallet(let wallet) = walletSelection { wallet } else { nil }
    }
}
