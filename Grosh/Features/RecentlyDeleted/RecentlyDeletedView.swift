import SwiftData
import SwiftUI

/// Account → Recently Deleted: the deleted wallets, each expanding to the transactions deleted with it, and the
/// transactions deleted on their own, each with the days it has left. Swipe or long-press an item to restore it or
/// delete it forever; Empty Bin removes everything. Use inside a `NavigationStack`.
struct RecentlyDeletedView: View {
    @Query(RecentlyDeleted.deletedWallets) private var wallets: [Wallet]
    @Query(RecentlyDeleted.deletedTransactions) private var transactions: [Transaction]

    @Environment(\.modelContext) private var context
    @State private var pendingRemoval: PendingRemoval?
    @State private var errorMessage: String?

    var body: some View {
        let bin = RecentlyDeleted(wallets: wallets, transactions: transactions)
        let now = Date.now

        List {
            if !bin.wallets.isEmpty {
                Section {
                    ForEach(bin.wallets) { wallet in
                        DisclosureGroup {
                            ForEach(wallet.transactionsDeletedWithIt) { transaction in
                                TransactionRow(transaction: transaction, showsDay: true)
                            }
                        } label: {
                            DeletedWalletRow(wallet: wallet, now: now)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete Forever", systemImage: "trash", role: .destructive) {
                                        pendingRemoval = .wallet(wallet)
                                    }
                                    Button("Restore", systemImage: "arrow.uturn.backward") {
                                        perform { try wallet.restore() }
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button("Restore", systemImage: "arrow.uturn.backward") {
                                        perform { try wallet.restore() }
                                    }
                                    Button("Delete Forever", systemImage: "trash", role: .destructive) {
                                        pendingRemoval = .wallet(wallet)
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Wallets")
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
                                Button("Delete Forever", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .transaction(transaction)
                                }
                                if transaction.restoreBlocker == nil {
                                    Button("Restore", systemImage: "arrow.uturn.backward") {
                                        perform { try transaction.restore() }
                                    }
                                    .tint(.blue)
                                }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    perform { try transaction.restore() }
                                }
                                .disabled(transaction.restoreBlocker != nil)
                                Button("Delete Forever", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .transaction(transaction)
                                }
                            }
                    }
                } header: {
                    Text("Transactions")
                } footer: {
                    RecentlyDeletedFooter()
                }
            }
        }
        .overlay {
            if bin.isEmpty {
                ContentUnavailableView(
                    "Nothing Recently Deleted",
                    systemImage: "trash",
                    description: Text("Deleted wallets and transactions wait here for \(RecentlyDeleted.keptDays) days before they're removed for good.")
                )
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty Bin", role: .destructive) { pendingRemoval = .everything }
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
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(removal.message)
        }
        .errorAlert("Couldn't Change Recently Deleted", message: $errorMessage)
    }

    private func remove(_ removal: PendingRemoval) {
        perform {
            switch removal {
            case .wallet(let wallet): try wallet.deleteForever(in: context)
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
            errorMessage = error.localizedDescription
        }
    }
}

/// How long items wait, and how to restore or delete one.
private struct RecentlyDeletedFooter: View {
    var body: some View {
        Text("Items are removed for good after \(RecentlyDeleted.keptDays) days. Swipe an item to restore it or delete it forever.")
    }
}

/// What Delete Forever or Empty Bin is waiting for the user to confirm.
private enum PendingRemoval {
    case wallet(Wallet)
    case transaction(Transaction)
    case everything

    var title: String {
        switch self {
        case .wallet: String(localized: "Delete this wallet forever?")
        case .transaction: String(localized: "Delete this transaction forever?")
        case .everything: String(localized: "Empty Recently Deleted?")
        }
    }

    var message: String {
        switch self {
        case .wallet: String(localized: "The wallet and its transactions will be removed for good. This can't be undone.")
        case .transaction: String(localized: "The transaction will be removed for good. This can't be undone.")
        case .everything: String(localized: "Every wallet and transaction in Recently Deleted will be removed for good. This can't be undone.")
        }
    }

    var buttonTitle: String {
        switch self {
        case .wallet, .transaction: String(localized: "Delete Forever")
        case .everything: String(localized: "Empty Bin")
        }
    }
}

/// A deleted wallet: its icon and name, how many transactions went with it, and the days it has left.
private struct DeletedWalletRow: View {
    let wallet: Wallet
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            SymbolCircle(symbolName: wallet.symbolName, color: wallet.color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name)
                    .lineLimit(1)
                Text(transactionCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            DaysLeftText(deletedAt: wallet.deletedAt, now: now)
        }
        .accessibilityElement(children: .combine)
    }

    private var transactionCount: String {
        let count = wallet.transactionsDeletedWithIt.count
        return count == 1
            ? String(localized: "1 transaction")
            : String(localized: "\(count) transactions")
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
                    Text("Restore its wallet first")
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

/// "N days left" before an item in Recently Deleted is removed for good.
private struct DaysLeftText: View {
    let deletedAt: Date?
    let now: Date

    var body: some View {
        let days = deletedAt.map { RecentlyDeleted.daysLeft(since: $0, now: now) } ?? RecentlyDeleted.keptDays
        Text(days == 1 ? String(localized: "1 day left") : String(localized: "\(days) days left"))
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
