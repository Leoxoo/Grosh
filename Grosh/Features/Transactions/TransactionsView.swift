import SwiftData
import SwiftUI

/// The Transactions tab: the list, and the selected transaction's detail beside it on iPad and Mac
/// (pushed on iPhone).
struct TransactionsView: View {
    @State private var selectedTransaction: Transaction?

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
                        "No Transaction Selected",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Select a transaction to see its details.")
                    )
                }
            }
            .id(selectedTransaction?.persistentModelID)
        }
    }
}

#Preview {
    TransactionsView()
        .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
