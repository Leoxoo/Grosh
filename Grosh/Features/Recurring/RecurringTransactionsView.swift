import SwiftData
import SwiftUI

/// Account → Recurring transactions: every schedule, grouped by Kind and in the order it was added within each group.
/// A paused one, whose wallet is archived, shows muted. A deleted one waits in Recently Deleted. A wallet filter in the
/// toolbar narrows the list to one wallet's schedules. Tap one to see what it has made, swipe one to duplicate it, and
/// add one with the plus.
struct RecurringTransactionsView: View {
    @Query(RecurringTransaction.notDeleted) private var recurring: [RecurringTransaction]
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @State private var editorMode: RecurringTransactionEditor.Mode?
    /// The wallet the list is narrowed to, or `nil` for every wallet. Each time the screen opens it shows every wallet.
    @State private var walletFilter: Wallet?
    /// A save can change an estimate or a Purchase's progress, so the figures are worked out anew after each one.
    @StoreSaves private var saves
    /// The figures of every schedule (``RecurringFigures``), worked out once per save of the store rather than on each
    /// draw, such as when the wallet filter or a sheet changes.
    @State private var figures = DrawingCache<AsSaved, RecurringFigures>()

    private var groups: [RecurringListing.KindGroup] {
        RecurringListing.groups(of: recurring, wallet: walletFilter)
    }

    var body: some View {
        let groups = self.groups
        let figures = self.figures.value(for: AsSaved(recurring, saves: saves)) { RecurringFigures(recurring) }
        List {
            ForEach(groups) { group in
                Section(group.kind.sectionTitle) {
                    GroupedForEach(group.items) { item in
                        NavigationLink {
                            RecurringTransactionDetailView(recurring: item)
                        } label: {
                            RecurringTransactionRow(
                                recurring: item, startingAmount: figures.startingAmount(of: item),
                                progress: figures.purchaseProgress(of: item)
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button(Strings.Common.duplicate, systemImage: "doc.on.doc") {
                                editorMode = .duplicate(item)
                            }
                        }
                    }
                }
            }
        }
        .roundedSectionsListStyle()
        .overlay {
            if recurring.isEmpty {
                ContentUnavailableView {
                    Label(Strings.Recurring.noRecurring, systemImage: "repeat")
                } description: {
                    Text(Strings.Recurring.noRecurringDescription)
                } actions: {
                    Button(Strings.Recurring.addRecurring) { editorMode = .add }
                }
            } else if groups.isEmpty, let walletFilter {
                ContentUnavailableView {
                    Label(Strings.Recurring.noRecurring, systemImage: "repeat")
                } description: {
                    Text(Strings.Recurring.noneFromWallet(walletFilter.name))
                }
            }
        }
        .navigationTitle(Strings.Screens.recurringTransactions)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                walletMenu
                Button(Strings.Recurring.addRecurring, systemImage: "plus") { editorMode = .add }
            }
        }
        .sheet(item: $editorMode) { mode in
            RecurringTransactionEditor(mode: mode)
        }
    }

    /// Narrows the list to every wallet, or to one unarchived wallet.
    private var walletMenu: some View {
        Menu {
            Picker(Strings.Common.wallet, selection: $walletFilter) {
                Text(Strings.Recurring.allWallets).tag(Wallet?.none)
                ForEach(wallets) { wallet in
                    Label(wallet.name, systemImage: wallet.symbolName).tag(Optional(wallet))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(Strings.Common.wallet, systemImage: walletFilter == nil ? "wallet.bifold" : "wallet.bifold.fill")
        }
        .accessibilityValue(walletFilter?.name ?? String(localized: Strings.Recurring.allWallets))
    }
}

/// One Recurring transaction in the list: its icon, name, wallet and next day, and its amount. A varying Bill shows its
/// estimate while it has one, as the transactions it makes will.
struct RecurringTransactionRow: View {
    let recurring: RecurringTransaction
    /// What its transactions start at now, its estimate for a varying Bill (``RecurringFigures``).
    let startingAmount: Money
    /// A Purchase's progress, or `nil` for any other Kind.
    let progress: PurchaseProgress?

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
                if let progress {
                    Text(progress.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(amount: startingAmount)
        }
        .contentShape(Rectangle())
        .opacity(recurring.isPaused ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    /// The wallet and the next day it falls due, such as "Checking · Next Nov 4, 2026", or "Paused" while its wallet
    /// is archived.
    private var detail: String {
        let wallet = recurring.wallet?.name ?? String(localized: Strings.Recurring.noWallet)
        if recurring.isPaused {
            return String(localized: Strings.Recurring.walletPaused(wallet))
        }
        guard let next = recurring.nextDueDay else {
            return String(localized: Strings.Recurring.walletEnded(wallet))
        }
        let day = next.date().formatted(.dateTime.day().month(.abbreviated).year())
        return String(localized: Strings.Recurring.walletNext(wallet, day))
    }
}
