import SwiftData
import SwiftUI

/// Picks an existing transaction to attach to a Recurring transaction: any transaction in any wallet, outside Recently
/// Deleted and not held by another Recurring transaction, newest first. The filters open on the schedule's wallet and
/// category, and the user can change or clear them. Tapping one attaches it and closes the picker.
struct LinkExistingTransactionView: View {
    let recurring: RecurringTransaction

    @Environment(\.modelContext) private var context
    @NotDeletedTransactions private var transactions: [Transaction]

    var body: some View {
        TransactionPickerSheet(
            Strings.Recurring.linkTransaction,
            candidates: transactions.filter(\.isAttachable),
            startingFilter: recurring.linkPickerFilter,
            emptyTitle: Strings.Recurring.noTransactionsToLink,
            emptyDescription: Strings.Recurring.noTransactionsToLinkDescription,
            errorTitle: Strings.Recurring.couldntLink,
            failure: ("Linking a transaction to a Recurring transaction", Log.recurring)
        ) { transaction in
            try recurring.attach(transaction, in: context)
        }
    }
}
