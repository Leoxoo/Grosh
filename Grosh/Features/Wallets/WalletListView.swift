import SwiftData
import SwiftUI

/// Account → Wallets: every wallet in the user's order. Drag to reorder, tap to edit, swipe to archive or delete.
struct WalletListView: View {
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @Query(Wallet.archived) private var archivedWallets: [Wallet]
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
                        WalletRow(wallet: wallet, today: today, showsTotalStatus: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(Strings.Common.delete, systemImage: "trash") { deleting = wallet }
                            .tint(.destructive)
                        Button(Strings.Common.archive, systemImage: "archivebox") { perform { try wallet.archive(today: today) } }
                            .tint(.archiveAction)
                    }
                    .contextMenu {
                        Button(Strings.Common.edit, systemImage: "pencil") { editorMode = .edit(wallet) }
                        Button(Strings.Common.archive, systemImage: "archivebox") { perform { try wallet.archive(today: today) } }
                        Button(Strings.Common.delete, systemImage: "trash", role: .destructive) { deleting = wallet }
                    }
                }
                .onMove { source, destination in
                    perform { try Wallet.move(wallets, fromOffsets: source, toOffset: destination) }
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
                            WalletRow(wallet: wallet, today: today)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(Strings.Common.delete, systemImage: "trash") { deleting = wallet }
                                .tint(.destructive)
                            Button(Strings.Common.unarchive, systemImage: "tray.and.arrow.up") {
                                perform { try wallet.unarchive(today: today) }
                            }
                            .tint(.unarchiveAction)
                        }
                        .contextMenu {
                            Button(Strings.Common.unarchive, systemImage: "tray.and.arrow.up") {
                                perform { try wallet.unarchive(today: today) }
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

    /// Runs a change, or shows why it was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Log.store.failed("Changing a wallet", error)
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        WalletListView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
