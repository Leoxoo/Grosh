import os
import SwiftUI

/// A sheet that picks one existing transaction from `candidates`, newest first, narrowed by search and the filters.
/// Tapping one calls `pick` and closes the sheet, or shows why `pick` refused it. With no candidates at all it says so
/// with `emptyTitle` and `emptyDescription`.
struct TransactionPickerSheet: View {
    let title: LocalizedStringResource
    /// Every transaction that may be picked, before search and filters.
    let candidates: [Transaction]
    let emptyTitle: LocalizedStringResource
    let emptyDescription: LocalizedStringResource
    /// Whether every candidate is in the same wallet, so the rows never show a wallet's icon.
    var candidatesShareAWallet = false
    let errorTitle: LocalizedStringResource
    /// What picking is called in the log, and where it is logged, when `pick` fails.
    let failure: (what: String, log: Logger)
    let pick: (Transaction) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: TransactionFilter
    @State private var errorMessage: String?

    init(
        _ title: LocalizedStringResource,
        candidates: [Transaction],
        startingFilter: TransactionFilter = TransactionFilter(),
        emptyTitle: LocalizedStringResource,
        emptyDescription: LocalizedStringResource,
        candidatesShareAWallet: Bool = false,
        errorTitle: LocalizedStringResource,
        failure: (what: String, log: Logger),
        pick: @escaping (Transaction) throws -> Void
    ) {
        self.title = title
        self.candidates = candidates
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.candidatesShareAWallet = candidatesShareAWallet
        self.errorTitle = errorTitle
        self.failure = failure
        self.pick = pick
        _filter = State(initialValue: startingFilter)
    }

    var body: some View {
        let shown = candidates.matching(filter).inListOrder()
        NavigationStack {
            Group {
                if shown.isEmpty {
                    if filter.isOn {
                        NoMatchingTransactionsView(filter: filter)
                    } else {
                        ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyDescription))
                    }
                } else {
                    List(shown) { transaction in
                        Button {
                            choose(transaction)
                        } label: {
                            TransactionRow(
                                transaction: transaction,
                                showsDay: true,
                                showsWalletIcon: !candidatesShareAWallet && filter.wallet == nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $filter.searchText, prompt: Strings.Common.searchPrompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    TransactionFilterButton(filter: $filter)
                }
            }
            .errorAlert(errorTitle, message: $errorMessage)
        }
    }

    private func choose(_ transaction: Transaction) {
        if failure.log.perform(failure.what, errorMessage: &errorMessage, { try pick(transaction) }) {
            dismiss()
        }
    }
}
