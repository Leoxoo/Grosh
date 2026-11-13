import SwiftData
import SwiftUI

/// Picks an existing deposit to move into an Expense as a Reimbursement: money that came into the Expense's own wallet,
/// outside Recently Deleted, newest first (``Transaction/reimbursementMoveInBlocker(into:)``). Tapping
/// one makes its amount, day and note an entry on the Expense, sends it to Recently Deleted, and closes the picker.
struct ReimbursementMoveInPicker: View {
    let expense: Transaction

    @Environment(\.modelContext) private var context
    @NotDeletedTransactions private var transactions: [Transaction]

    var body: some View {
        TransactionPickerSheet(
            Strings.Reimbursements.moveTransactionIn,
            candidates: transactions.filter { $0.canBeMovedIntoReimbursement(of: expense) },
            emptyTitle: Strings.Reimbursements.noTransactionsToMoveIn,
            emptyDescription: Strings.Reimbursements.noTransactionsToMoveInDescription,
            errorTitle: Strings.Reimbursements.couldntMoveIn,
            failure: "Moving a transaction in", log: Log.store
        ) { deposit in
            try Reimbursement.moveIn(deposit, to: expense, in: context)
        }
    }
}
