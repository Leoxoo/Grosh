import SwiftData
import SwiftUI

/// The Transactions tab: the list, and the selected transaction's detail beside it on iPad and Mac
/// (pushed on iPhone).
struct TransactionsView: View {
    @State private var selectedTransaction: Transaction?
    #if os(macOS)
    /// How far the app's sidebar reaches over the tab from its leading edge, while the sidebar is open.
    @State private var appSidebarWidth: CGFloat = 0
    #endif

    var body: some View {
        NavigationSplitView {
            TransactionListView(selectedTransaction: $selectedTransaction)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            NavigationStack {
                if let selectedTransaction {
                    TransactionDetailView(transaction: selectedTransaction) {
                        self.selectedTransaction = nil
                    }
                } else {
                    ContentUnavailableView(
                        Strings.Transactions.noTransactionSelected,
                        systemImage: "list.bullet.rectangle",
                        description: Text(Strings.Transactions.selectTransactionDescription)
                    )
                }
            }
            .id(selectedTransaction?.persistentModelID)
            #if os(macOS)
            // The window takes its title from the detail, which has none while nothing is selected, so the window
            // would show the app's name. It names the tab instead, with a transaction open too.
            .navigationTitle(Strings.Common.transactions)
            #endif
        }
        .onAppear { Signpost.opening("Open Transactions") }
        #if os(macOS)
        // The app's sidebar floats over the tab, and a split view laid out under it pushes its detail the sidebar's
        // width away from the list. Beside the sidebar, the split view lays out as it does while the sidebar is closed.
        .padding(.leading, appSidebarWidth)
        .ignoresSafeArea(.container, edges: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.leading } action: { appSidebarWidth = $0 }
        #endif
    }
}

#Preview {
    TransactionsView()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
