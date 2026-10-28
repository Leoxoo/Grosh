import SwiftData
import SwiftUI

/// Account → Recently Deleted: the deleted wallets, each expanding to the transactions and Recurring transactions
/// deleted with it, and the Recurring transactions and transactions deleted on their own, each with the days it has
/// left. Swipe or long-press an item to restore it or delete it forever; Empty Bin removes everything. Use inside a
/// `NavigationStack`.
struct RecentlyDeletedView: View {
    @Query(RecentlyDeleted.deletedWallets) private var wallets: [Wallet]
    @Query(RecentlyDeleted.deletedRecurring) private var recurring: [RecurringTransaction]
    @Query(RecentlyDeleted.deletedTransactions) private var transactions: [Transaction]

    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today
    @State private var pendingRemoval: PendingRemoval?
    @State private var errorMessage: String?

    var body: some View {
        let bin = RecentlyDeleted(wallets: wallets, transactions: transactions, recurring: recurring)
        // Days left run from the moment an item was deleted, not from a calendar day, so this reads the clock.
        let now = Date.now

        List {
            if !bin.wallets.isEmpty {
                Section {
                    ForEach(bin.wallets) { wallet in
                        let deletedWithIt = wallet.transactionsDeletedWithIt
                        DisclosureGroup {
                            ForEach(wallet.recurringDeletedWithIt) { schedule in
                                Label(schedule.name, systemImage: "repeat")
                            }
                            ForEach(deletedWithIt) { transaction in
                                // All from this wallet, which its row already names.
                                TransactionRow(transaction: transaction, showsDay: true, showsWalletIcon: false)
                            }
                        } label: {
                            DeletedWalletRow(wallet: wallet, transactionCount: deletedWithIt.count, now: now)
                                .swipeActions(edge: .trailing) {
                                    Button(Strings.RecentlyDeleted.deleteForever, systemImage: "trash", role: .destructive) {
                                        pendingRemoval = .wallet(wallet)
                                    }
                                    Button(Strings.Common.restore, systemImage: "arrow.uturn.backward") {
                                        perform { try wallet.restore(today: today) }
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button(Strings.Common.restore, systemImage: "arrow.uturn.backward") {
                                        perform { try wallet.restore(today: today) }
                                    }
                                    Button(Strings.RecentlyDeleted.deleteForever, systemImage: "trash", role: .destructive) {
                                        pendingRemoval = .wallet(wallet)
                                    }
                                }
                        }
                    }
                } header: {
                    Text(Strings.Screens.wallets)
                } footer: {
                    if bin.recurring.isEmpty && bin.transactions.isEmpty {
                        RecentlyDeletedFooter()
                    }
                }
            }

            if !bin.recurring.isEmpty {
                Section {
                    ForEach(bin.recurring) { schedule in
                        DeletedRecurringRow(recurring: schedule, now: now)
                            .swipeActions(edge: .trailing) {
                                Button(Strings.RecentlyDeleted.deleteForever, systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .recurring(schedule)
                                }
                                if schedule.restoreBlocker == nil {
                                    Button(Strings.Common.restore, systemImage: "arrow.uturn.backward") {
                                        perform { try schedule.restore(today: today) }
                                    }
                                    .tint(.blue)
                                }
                            }
                            .contextMenu {
                                Button(Strings.Common.restore, systemImage: "arrow.uturn.backward") {
                                    perform { try schedule.restore(today: today) }
                                }
                                .disabled(schedule.restoreBlocker != nil)
                                Button(Strings.RecentlyDeleted.deleteForever, systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .recurring(schedule)
                                }
                            }
                    }
                } header: {
                    Text(Strings.Screens.recurringTransactions)
                } footer: {
                    if bin.transactions.isEmpty {
                        RecentlyDeletedFooter()
                    }
                }
            }

            if !bin.transactions.isEmpty {
                Section {
                    ForEach(bin.transactions) { transaction in
                        DeletedTransactionRow(transaction: transaction, now: now)
                            .swipeActions(edge: .trailing) {
                                Button(Strings.RecentlyDeleted.deleteForever, systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .transaction(transaction)
                                }
                                if transaction.restoreBlocker == nil {
                                    Button(Strings.Common.restore, systemImage: "arrow.uturn.backward") {
                                        perform { try transaction.restore() }
                                    }
                                    .tint(.blue)
                                }
                            }
                            .contextMenu {
                                Button(Strings.Common.restore, systemImage: "arrow.uturn.backward") {
                                    perform { try transaction.restore() }
                                }
                                .disabled(transaction.restoreBlocker != nil)
                                Button(Strings.RecentlyDeleted.deleteForever, systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .transaction(transaction)
                                }
                            }
                    }
                } header: {
                    Text(Strings.Common.transactions)
                } footer: {
                    RecentlyDeletedFooter()
                }
            }
        }
        .overlay {
            if bin.isEmpty {
                ContentUnavailableView(
                    Strings.RecentlyDeleted.nothingRecentlyDeleted,
                    systemImage: "trash",
                    description: Text(Strings.RecentlyDeleted.emptyDescription(RecentlyDeleted.keptDays))
                )
            }
        }
        .navigationTitle(Strings.Screens.recentlyDeleted)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.RecentlyDeleted.emptyBin, role: .destructive) { pendingRemoval = .everything }
                    .disabled(bin.isEmpty)
            }
        }
        .confirmationDialog(
            pendingRemoval?.title ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button(removal.buttonTitle, role: .destructive) { remove(removal) }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: { removal in
            Text(removal.message)
        }
        .errorAlert(Strings.RecentlyDeleted.couldntChange, message: $errorMessage)
    }

    private func remove(_ removal: PendingRemoval) {
        perform {
            switch removal {
            case .wallet(let wallet): try wallet.deleteForever(in: context)
            case .recurring(let schedule): try schedule.deleteForever(in: context)
            case .transaction(let transaction): try transaction.deleteForever(in: context)
            case .everything: try RecentlyDeleted.empty(in: context)
            }
        }
    }

    /// Runs a change, or shows why it was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Log.store.failed("Changing Recently Deleted", error)
            errorMessage = error.localizedDescription
        }
    }
}

/// How long items wait, and how to restore or delete one.
private struct RecentlyDeletedFooter: View {
    var body: some View {
        Text(Strings.RecentlyDeleted.footer(RecentlyDeleted.keptDays))
    }
}

/// What Delete Forever or Empty Bin is waiting for the user to confirm.
private enum PendingRemoval {
    case wallet(Wallet)
    case recurring(RecurringTransaction)
    case transaction(Transaction)
    case everything

    var title: String {
        switch self {
        case .wallet: String(localized: Strings.RecentlyDeleted.deleteWalletForever)
        case .recurring: String(localized: Strings.RecentlyDeleted.deleteRecurringForever)
        case .transaction: String(localized: Strings.RecentlyDeleted.deleteTransactionForever)
        case .everything: String(localized: Strings.RecentlyDeleted.emptyQuestion)
        }
    }

    var message: String {
        switch self {
        case .wallet: String(localized: Strings.RecentlyDeleted.walletRemovalMessage)
        case .recurring: String(localized: Strings.RecentlyDeleted.recurringRemovalMessage)
        case .transaction: String(localized: Strings.RecentlyDeleted.transactionRemovalMessage)
        case .everything: String(localized: Strings.RecentlyDeleted.everythingRemovalMessage)
        }
    }

    var buttonTitle: String {
        switch self {
        case .wallet, .recurring, .transaction: String(localized: Strings.RecentlyDeleted.deleteForever)
        case .everything: String(localized: Strings.RecentlyDeleted.emptyBin)
        }
    }
}

/// A deleted wallet: its icon and name, how many transactions went with it, and the days it has left.
private struct DeletedWalletRow: View {
    let wallet: Wallet
    /// How many transactions were deleted with it.
    let transactionCount: Int
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            SymbolCircle(symbolName: wallet.symbolName, color: wallet.color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name)
                    .lineLimit(1)
                Text(transactionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            DaysLeftText(deletedAt: wallet.deletedAt, now: now)
        }
        .accessibilityElement(children: .combine)
    }

    private var transactionSummary: String {
        String(localized: Strings.RecentlyDeleted.transactionCount(transactionCount))
    }
}

/// A transaction deleted on its own, as every list shows it, with the days it has left and, while its wallet is in
/// Recently Deleted too, that the wallet has to be restored first.
private struct DeletedTransactionRow: View {
    let transaction: Transaction
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TransactionRow(transaction: transaction, showsDay: true)
            HStack {
                if transaction.restoreBlocker == .walletIsDeleted {
                    Text(Strings.RecentlyDeleted.restoreWalletFirst)
                        .foregroundStyle(.orange)
                }
                Spacer()
                DaysLeftText(deletedAt: transaction.deletedAt, now: now)
            }
            .font(.caption)
            .padding(.leading, 44)
        }
    }
}

/// A Recurring transaction deleted on its own: its name, category and repeat, the days it has left and, while its
/// wallet is in Recently Deleted too, that the wallet has to be restored first.
private struct DeletedRecurringRow: View {
    let recurring: RecurringTransaction
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                CategoryIcon(category: recurring.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recurring.name)
                        .lineLimit(1)
                    Text(recurring.schedule.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                if recurring.restoreBlocker == .walletIsDeleted {
                    Text(Strings.RecentlyDeleted.restoreWalletFirst)
                        .foregroundStyle(.orange)
                }
                Spacer()
                DaysLeftText(deletedAt: recurring.deletedAt, now: now)
            }
            .font(.caption)
            .padding(.leading, 44)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "N days left" before an item in Recently Deleted is removed for good.
private struct DaysLeftText: View {
    let deletedAt: Date?
    let now: Date

    var body: some View {
        let days = deletedAt.map { RecentlyDeleted.daysLeft(since: $0, now: now) } ?? RecentlyDeleted.keptDays
        Text(Strings.RecentlyDeleted.daysLeft(days))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(days <= 3 ? .red : .secondary)
    }
}

#Preview {
    NavigationStack {
        RecentlyDeletedView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
