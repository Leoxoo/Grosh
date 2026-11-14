import SwiftData
import SwiftUI

/// Account → Wallets: every wallet in the user's order. Drag to reorder, tap to edit, swipe to archive or delete.
struct WalletListView: View {
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @Query(Wallet.archived) private var archivedWallets: [Wallet]
    /// The wallets' balances, from the saved month totals.
    @SavedWalletBalances private var balances
    @Environment(\.today) private var today
    @State private var editorMode: EditorMode<Wallet>?
    @State private var errorMessage: String?
    /// The wallet waiting for the user to confirm deleting it.
    @State private var deleting: Wallet?

    var body: some View {
        List {
            Section {
                ForEach(wallets) { wallet in
                    Button {
                        editorMode = .edit(wallet)
                    } label: {
                        WalletRow(wallet: wallet, balances: balances, showsTotalStatus: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(Strings.Common.delete, systemImage: "trash") { deleting = wallet }
                            .tint(.destructive)
                        Button(Strings.Common.archive, systemImage: "archivebox") { Log.store.perform("Changing a wallet", errorMessage: &errorMessage) { try wallet.archive(today: today) } }
                            .tint(.archiveAction)
                    }
                    .contextMenu {
                        Button(Strings.Common.edit, systemImage: "pencil") { editorMode = .edit(wallet) }
                        Button(Strings.Common.archive, systemImage: "archivebox") { Log.store.perform("Changing a wallet", errorMessage: &errorMessage) { try wallet.archive(today: today) } }
                        Button(Strings.Common.delete, systemImage: "trash", role: .destructive) { deleting = wallet }
                    }
                }
                .onMove { source, destination in
                    Log.store.perform("Changing a wallet", errorMessage: &errorMessage) { try Wallet.move(wallets, fromOffsets: source, toOffset: destination) }
                }
            } footer: {
                if wallets.count > 1 {
                    Text(Strings.Wallets.reorderFooter)
                }
            }

            if !archivedWallets.isEmpty {
                Section {
                    ForEach(archivedWallets) { wallet in
                        Button {
                            editorMode = .edit(wallet)
                        } label: {
                            WalletRow(wallet: wallet, balances: balances)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(Strings.Common.delete, systemImage: "trash") { deleting = wallet }
                                .tint(.destructive)
                            Button(Strings.Common.unarchive, systemImage: "tray.and.arrow.up") {
                                Log.store.perform("Changing a wallet", errorMessage: &errorMessage) { try wallet.unarchive(today: today) }
                            }
                            .tint(.unarchiveAction)
                        }
                        .contextMenu {
                            Button(Strings.Common.unarchive, systemImage: "tray.and.arrow.up") {
                                Log.store.perform("Changing a wallet", errorMessage: &errorMessage) { try wallet.unarchive(today: today) }
                            }
                            Button(Strings.Common.delete, systemImage: "trash", role: .destructive) { deleting = wallet }
                        }
                    }
                } header: {
                    Text(Strings.Common.archived)
                } footer: {
                    Text(Strings.Wallets.archivedSectionFooter)
                }
            }
        }
        .overlay {
            if wallets.isEmpty && archivedWallets.isEmpty {
                ContentUnavailableView {
                    Label(Strings.Wallets.noWallets, systemImage: "wallet.bifold")
                } description: {
                    Text(Strings.Wallets.noWalletsDescription)
                } actions: {
                    Button(Strings.Wallets.addWallet) { editorMode = .add }
                }
            }
        }
        .navigationTitle(Strings.Screens.wallets)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.Wallets.addWallet, systemImage: "plus") { editorMode = .add }
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            #endif
        }
        .sheet(item: $editorMode) { mode in
            WalletEditor(mode: mode)
        }
        .walletDeleteDialog($deleting)
        .errorAlert(Strings.Wallets.couldntChange, message: $errorMessage)
    }
}

#Preview {
    NavigationStack {
        WalletListView()
    }
    .modelContainer(try! StoreOpening.open(inMemory: true))
}
