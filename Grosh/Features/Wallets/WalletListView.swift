import SwiftData
import SwiftUI

/// Account → Wallets: every wallet in the user's order. Drag to reorder, tap to edit, swipe to archive or delete.
struct WalletListView: View {
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @Query(Wallet.archived) private var archivedWallets: [Wallet]
    @State private var editorMode: EditorMode<Wallet>?
    @State private var errorMessage: String?
    /// The wallet waiting for the user to confirm deleting it.
    @State private var deleting: Wallet?

    private var today: CalendarDay { .today }

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
                        Button("Delete", systemImage: "trash") { deleting = wallet }
                            .tint(.red)
                        Button("Archive", systemImage: "archivebox") { perform { try wallet.archive() } }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorMode = .edit(wallet) }
                        Button("Archive", systemImage: "archivebox") { perform { try wallet.archive() } }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = wallet }
                    }
                }
                .onMove { source, destination in
                    perform { try Wallet.move(wallets, fromOffsets: source, toOffset: destination) }
                }
            } footer: {
                if wallets.count > 1 {
                    Text("Drag to reorder. Home and every wallet picker use this order.")
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
                            Button("Delete", systemImage: "trash") { deleting = wallet }
                                .tint(.red)
                            Button("Unarchive", systemImage: "tray.and.arrow.up") { perform { try wallet.unarchive() } }
                                .tint(.green)
                        }
                        .contextMenu {
                            Button("Unarchive", systemImage: "tray.and.arrow.up") { perform { try wallet.unarchive() } }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = wallet }
                        }
                    }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived wallets are left out of the Total and the pickers. Their transactions are kept.")
                }
            }
        }
        .overlay {
            if wallets.isEmpty && archivedWallets.isEmpty {
                ContentUnavailableView {
                    Label("No Wallets", systemImage: "wallet.bifold")
                } description: {
                    Text("Add a wallet for each place you keep money.")
                } actions: {
                    Button("Add Wallet") { editorMode = .add }
                }
            }
        }
        .navigationTitle("Wallets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Wallet", systemImage: "plus") { editorMode = .add }
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
        .errorAlert("Couldn't Change Wallet", message: $errorMessage)
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

#Preview {
    NavigationStack {
        WalletListView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
