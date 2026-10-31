import SwiftData
import SwiftUI

/// One transaction with all its fields, its Related transactions, and Edit, Duplicate, Split and Delete.
/// Use inside a `NavigationStack`.
struct TransactionDetailView: View {
    let transaction: Transaction
    /// Called once the transaction is deleted. Without it, the screen dismisses itself.
    var didDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// The editor Edit opened, while it is open.
    @State private var editing: TransactionEditFlow?
    @State private var isDuplicating = false
    @State private var isSplitting = false
    @State private var isEnteringAmount = false
    /// What the Loan or Debt section opened, while it is open.
    @State private var loanOrDebtAction: LoanOrDebtAction?
    /// What the Reimbursement section opened, while it is open.
    @State private var reimbursementAction: ReimbursementAction?

    var body: some View {
        Group {
            if transaction.isDeleted || transaction.modelContext == nil || transaction.isInRecentlyDeleted {
                ContentUnavailableView(Strings.Transactions.transactionDeleted, systemImage: "trash")
            } else {
                details
            }
        }
        .navigationTitle(Strings.Transactions.transaction)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { flow in
            switch flow {
            case .addSheet: TransactionEditor(mode: .edit(transaction))
            case .startingBalance: StartingBalanceEditor(transaction: transaction)
            case .transferHalf: TransferHalfEditor(transaction: transaction)
            }
        }
        .sheet(isPresented: $isDuplicating) {
            TransactionEditor(mode: .duplicate(transaction))
        }
        .sheet(isPresented: $isSplitting) {
            SplitSheet(transaction: transaction)
        }
        .sheet(isPresented: $isEnteringAmount) {
            EstimatedAmountEditor(transaction: transaction)
        }
        .loanOrDebtSheets(for: transaction, action: $loanOrDebtAction)
        .reimbursementSheets(for: transaction, action: $reimbursementAction)
    }

    private var details: some View {
        // Worked out once for the whole screen: on a linked Expense or Income, whether it is a part of a Split reads the
        // store.
        let isSplitPart = transaction.isSplitPart
        let editFlow = transaction.editFlow(isSplitPart: isSplitPart)
        let canBeDuplicated = transaction.canBeDuplicated(editFlow: editFlow)
        return List {
            Section {
                TransactionDetailHeader(transaction: transaction)
            }

            if transaction.isExcludedFromReport {
                Section {
                    ExcludedFromReportBanner()
                }
            }

            if transaction.isEstimated {
                Section {
                    Button(Strings.Transactions.enterAmount, systemImage: "checkmark.circle") {
                        isEnteringAmount = true
                    }
                } footer: {
                    Text(Strings.Transactions.estimatedFooter)
                }
            }

            BalanceChangeSection(transaction: transaction)

            LoanOrDebtSection(transaction: transaction, action: $loanOrDebtAction)

            ReimbursementSection(transaction: transaction, action: $reimbursementAction)

            Section {
                fields
            }

            RelatedTransactionsSection(transaction: transaction, isSplitPart: isSplitPart)

            Section {
                if canBeDuplicated {
                    Button(Strings.Common.duplicate, systemImage: "plus.square.on.square") {
                        isDuplicating = true
                    }
                    .fullWidthRowButton()
                }
                if transaction.canBeSplit(editFlow: editFlow) {
                    Button(Strings.Transactions.split, systemImage: "square.split.2x1") {
                        isSplitting = true
                    }
                    .fullWidthRowButton()
                }
                TransactionDeleteButton(transaction: transaction) {
                    if let didDelete { didDelete() } else { dismiss() }
                }
                .fullWidthRowButton()
            } footer: {
                if canBeDuplicated {
                    Text(Strings.Transactions.duplicateFooter)
                }
            }
        }
        #if os(macOS)
        // A readable-width column, pinned to the pane's left edge.
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        .toolbar {
            if let editFlow {
                ToolbarItem(placement: .primaryAction) {
                    Button(Strings.Common.edit) { editing = editFlow }
                }
            }
        }
    }

    /// Every other field of the transaction. Empty optional fields are left out.
    @ViewBuilder
    private var fields: some View {
        if let wallet = transaction.wallet {
            WalletLabel(title: Strings.Common.wallet, wallet: wallet)
        }
        if let card = transaction.card {
            LabeledContent(Strings.Common.card) {
                HStack(spacing: 6) {
                    CardMark(image: card.image, height: 18) {
                        Image(systemName: Card.symbolName)
                            .foregroundStyle(card.color.color)
                    }
                    Text(card.displayName)
                }
            }
        }
        if !transaction.note.isEmpty {
            LabeledContent(Strings.Common.note, value: transaction.note)
        }
        if !transaction.withName.isEmpty {
            LabeledContent(Strings.Common.with, value: transaction.withName)
        }
        if !transaction.eventName.isEmpty {
            LabeledContent(Strings.Common.event, value: transaction.eventName)
        }
    }
}

/// The category, the amount in color, and the date.
private struct TransactionDetailHeader: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 16) {
            CategoryIcon(category: transaction.category, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.categoryName)
                    .font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    AmountText(amount: transaction.amount)
                        .font(.title.bold())
                    ReimbursementNetText(transaction: transaction)
                        .font(.title3)
                }
                Text(transaction.day.date().formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Says the transaction is left out of income and spending, but still in its wallet's balance.
private struct ExcludedFromReportBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.Common.excludedFromReport)
                    .font(.headline)
                Text(Strings.Common.excludedFromReportFooter)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "eye.slash")
                .foregroundStyle(.attention)
        }
    }
}

extension TransactionEditFlow: Identifiable {
    var id: Self { self }
}

extension View {
    /// On Mac, a list button fills its row and is clickable across it, rather than floating as a bordered button.
    fileprivate func fullWidthRowButton() -> some View {
        #if os(macOS)
        buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        #else
        self
        #endif
    }
}
