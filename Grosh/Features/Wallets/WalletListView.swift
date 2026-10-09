import SwiftData
import SwiftUI

/// Account → Wallets: every wallet in the user's order. Drag to reorder, tap to edit, swipe to archive.
struct WalletListView: View {
    @Environment(\.modelContext) private var context
    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @Query(filter: #Predicate<Wallet> { $0.isArchived }, sort: Wallet.userOrder) private var archivedWallets: [Wallet]
    @State private var editorMode: WalletEditor.Mode?

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
                        Button("Archive", systemImage: "archivebox") { wallet.archive() }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorMode = .edit(wallet) }
                        Button("Archive", systemImage: "archivebox") { wallet.archive() }
                    }
                }
                .onMove { source, destination in
                    Wallet.move(wallets, fromOffsets: source, toOffset: destination)
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
                            Button("Unarchive", systemImage: "tray.and.arrow.up") { unarchive(wallet) }
                                .tint(.green)
                        }
                        .contextMenu {
                            Button("Unarchive", systemImage: "tray.and.arrow.up") { unarchive(wallet) }
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
    }

    private func unarchive(_ wallet: Wallet) {
        try? wallet.unarchive(in: context)
    }
}

#Preview {
    NavigationStack {
        WalletListView()
    }
    .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
