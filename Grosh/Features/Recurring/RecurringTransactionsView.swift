import SwiftData
import SwiftUI

/// Account → Recurring transactions: every schedule, grouped by Kind and in the order it was added within each group.
/// A paused one, whose wallet is archived, shows muted. A deleted one waits in Recently Deleted. A wallet filter in the
/// toolbar narrows the list to one wallet's schedules. Tap one to see what it has made, and add one with the plus.
struct RecurringTransactionsView: View {
    @Query(filter: #Predicate<RecurringTransaction> { $0.deletedAt == nil }, sort: \RecurringTransaction.createdAt)
    private var recurring: [RecurringTransaction]
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @State private var editorMode: EditorMode<RecurringTransaction>?
    /// The wallet the list is narrowed to, or `nil` for every wallet. Each time the tab opens it shows every wallet.
    @State private var walletFilter: Wallet?

    private var groups: [RecurringListing.KindGroup] {
        RecurringListing.groups(of: recurring, wallet: walletFilter)
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.kind.sectionTitle) {
                    ForEach(group.items) { item in
                        NavigationLink {
                            RecurringTransactionDetailView(recurring: item)
                        } label: {
                            RecurringTransactionRow(recurring: item)
                        }
                    }
                }
            }
        }
        .overlay {
            if recurring.isEmpty {
                ContentUnavailableView {
                    Label("No Recurring Transactions", systemImage: "repeat")
                } description: {
                    Text("Bills, subscriptions and income that repeat are added for you on their dates.")
                } actions: {
                    Button("Add Recurring Transaction") { editorMode = .add }
                }
            } else if groups.isEmpty, let walletFilter {
                ContentUnavailableView {
                    Label("No Recurring Transactions", systemImage: "repeat")
                } description: {
                    Text("None are paid from \(walletFilter.name).")
                }
            }
        }
        .navigationTitle("Recurring transactions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                walletMenu
                Button("Add Recurring Transaction", systemImage: "plus") { editorMode = .add }
            }
        }
        .sheet(item: $editorMode) { mode in
            RecurringTransactionEditor(mode: mode)
        }
    }

    /// Narrows the list to every wallet, or to one unarchived wallet.
    private var walletMenu: some View {
        Menu {
            Picker("Wallet", selection: $walletFilter) {
                Text("All wallets").tag(Wallet?.none)
                ForEach(wallets) { wallet in
                    Label(wallet.name, systemImage: wallet.symbolName).tag(Optional(wallet))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Wallet", systemImage: walletFilter == nil ? "wallet.bifold" : "wallet.bifold.fill")
        }
        .accessibilityValue(walletFilter?.name ?? String(localized: "All wallets"))
    }
}

/// One Recurring transaction in the list: its icon, name, wallet and next day, and its signed amount.
struct RecurringTransactionRow: View {
    let recurring: RecurringTransaction

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: recurring.category, subscriptionIcon: recurring.subscriptionIcon)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(recurring.name)
                        .lineLimit(1)
                    if recurring.estimatesAmount {
                        EstimatedBadge()
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress = recurring.purchaseProgress {
                    Text(progress.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(amount: recurring.signedAmount)
        }
        .contentShape(Rectangle())
        .opacity(recurring.isPaused ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    /// The wallet and the next day it falls due, such as "Checking · Next Nov 4, 2026", or "Paused" while its wallet
    /// is archived.
    private var detail: String {
        let wallet = recurring.wallet?.name ?? String(localized: "No wallet")
        if recurring.isPaused {
            return String(localized: "\(wallet) · Paused")
        }
        guard let next = recurring.nextDueDay else {
            return String(localized: "\(wallet) · Ended")
        }
        let day = next.date().formatted(.dateTime.day().month(.abbreviated).year())
        return String(localized: "\(wallet) · Next \(day)")
    }
}
