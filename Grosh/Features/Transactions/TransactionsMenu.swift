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

    @State private var isPickingCustomRange = false
    @State private var isTransferring = false
    @State private var isAdjustingBalance = false

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Section {
                Menu {
                    Picker("Time Range", selection: presetSelection) {
                        ForEach(TimeRange.presets, id: \.self) { range in
                            Text(range.title).tag(Optional(range))
                        }
                    }
                    .pickerStyle(.inline)

                    Button {
                        isPickingCustomRange = true
                    } label: {
                        if case .custom = timeRange {
                            Label("Custom…", systemImage: "checkmark")
                        } else {
                            Text("Custom…")
                        }
                    }
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
        .sheet(isPresented: $isPickingCustomRange) {
            CustomRangeEditor(days: customRangeStart) { timeRange = .custom($0) }
        }
        .sheet(isPresented: $isTransferring) {
            TransferEditor(viewedWallet: viewedWallet)
        }
        .sheet(isPresented: $isAdjustingBalance) {
            AdjustBalanceEditor(viewedWallet: viewedWallet)
        }
    }

    /// The preset the time range is, or `nil` for a custom range, so the picker checks none of them.
    private var presetSelection: Binding<TimeRange?> {
        Binding(
            get: { TimeRange.presets.contains(timeRange) ? timeRange : nil },
            set: { if let range = $0 { timeRange = range } }
        )
    }

    private var viewsByCategory: Binding<Bool> {
        Binding(get: { grouping == .category }, set: { grouping = $0 ? .category : .day })
    }

    /// The days the custom range editor starts with: the current custom range, or this month so far.
    private var customRangeStart: ClosedRange<CalendarDay> {
        if case .custom(let days) = timeRange { return days }
        let today = CalendarDay.today
        return CalendarMonth(today).firstDay...today
    }

    /// The one wallet the tab is showing, or `nil` for the Total.
    private var viewedWallet: Wallet? {
        if case .wallet(let wallet) = walletSelection { wallet } else { nil }
    }
}

extension TimeRange {
    /// The range's name in the "…" menu.
    var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .quarter: String(localized: "Quarter")
        case .year: String(localized: "Year")
        case .all: String(localized: "All")
        case .custom: String(localized: "Custom")
        }
    }
}
