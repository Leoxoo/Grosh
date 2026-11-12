import os
import SwiftUI

/// A sheet that picks one existing transaction from `candidates`, newest first, narrowed by search and the filters.
/// Tapping one calls `pick` and closes the sheet, or shows why `pick` refused it. With no candidates at all it says so
/// with `emptyTitle` and `emptyDescription`.
struct TransactionPickerSheet: View {
    let title: LocalizedStringResource
    /// Every transaction that may be picked, before search and filters. Put in order once, when the sheet opens.
    let candidates: [Transaction]
    let emptyTitle: LocalizedStringResource
    let emptyDescription: LocalizedStringResource
    /// What picking is called in the log when `pick` fails.
    let failure: String
    let pick: (Transaction) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: TransactionFilter
    private var saver: SheetSaver

    init(
        _ title: LocalizedStringResource,
        candidates: [Transaction],
        startingFilter: TransactionFilter = TransactionFilter(),
        emptyTitle: LocalizedStringResource,
        emptyDescription: LocalizedStringResource,
        errorTitle: LocalizedStringResource,
        failure: String,
        log: Logger,
        pick: @escaping (Transaction) throws -> Void
    ) {
        self.title = title
        self.candidates = candidates
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.failure = failure
        saver = SheetSaver(errorTitle, log: log)
        self.pick = pick
        _filter = State(initialValue: startingFilter)
    }

    var body: some View {
        MadeOnce {
            PickerCandidates(candidates)
        } content: { candidates in
            list(TransactionListing.picking(candidates, filter: filter))
        }
    }

    private func list(_ listing: TransactionListing) -> some View {
        NavigationStack {
            Group {
                if listing.transactions.isEmpty {
                    if filter.isOn {
                        NoMatchingTransactionsView(filter: filter)
                    } else {
                        ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyDescription))
                    }
                } else {
                    List(listing.transactions) { transaction in
                        Button {
                            saver.save(failure) { try pick(transaction) }
                        } label: {
                            TransactionRow(
                                transaction: transaction,
                                showsDay: true,
                                showsWalletIcon: listing.mixesWallets,
                                listed: listing.listed
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
            .failureAlert(saver)
        }
    }
}
