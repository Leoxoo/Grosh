import SwiftData
import SwiftUI

/// One transaction with all its fields, its Related transactions, and Edit, Duplicate, Split and Delete.
/// Use inside a `NavigationStack`.
struct TransactionDetailView: View {
    let transaction: Transaction
    /// Called once the transaction is deleted. Without it, the screen dismisses itself.
    var didDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// The one sheet open over the detail, if any.
    @State private var sheet: TransactionDetailSheet?

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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit(.addSheet): TransactionEditor(mode: .edit(transaction))
            case .edit(.startingBalance): StartingBalanceEditor(transaction: transaction)
            case .edit(.transferHalf): TransferHalfEditor(transaction: transaction)
            case .duplicate: TransactionEditor(mode: .duplicate(transaction))
            case .split: SplitSheet(transaction: transaction)
            case .enterAmount: EstimatedAmountEditor(transaction: transaction)
            case .loanOrDebt(let action): action.sheet(for: transaction)
            case .reimbursement(let action): action.sheet(for: transaction)
            }
        }
    }

    /// What the Loan or Debt section has open: one case of ``sheet``.
    private var loanOrDebtAction: Binding<LoanOrDebtAction?> {
        Binding {
            if case .loanOrDebt(let action) = sheet { action } else { nil }
        } set: { action in
            sheet = action.map(TransactionDetailSheet.loanOrDebt)
        }
    }

    /// What the Reimbursement section has open: one case of ``sheet``.
    private var reimbursementAction: Binding<ReimbursementAction?> {
        Binding {
            if case .reimbursement(let action) = sheet { action } else { nil }
        } set: { action in
            sheet = action.map(TransactionDetailSheet.reimbursement)
        }
    }

    private var details: some View {
        let editFlow = transaction.editFlow
        let canBeDuplicated = transaction.canBeDuplicated
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
                        sheet = .enterAmount
                    }
                } footer: {
                    Text(Strings.Transactions.estimatedFooter)
                }
            }

            BalanceChangeSection(transaction: transaction)

            LoanOrDebtSection(transaction: transaction, action: loanOrDebtAction)

            ReimbursementSection(transaction: transaction, action: reimbursementAction)

            OwesMeSection(transaction: transaction)

            Section {
                fields
            }

            RelatedTransactionsSection(transaction: transaction)

            Section {
                if canBeDuplicated {
                    Button(Strings.Common.duplicate, systemImage: "plus.square.on.square") {
                        sheet = .duplicate
                    }
                    .fullWidthRowButton()
                }
                if transaction.canBeSplit {
                    Button(Strings.Transactions.split, systemImage: "square.split.2x1") {
                        sheet = .split
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
                    Button(Strings.Common.edit) { sheet = .edit(editFlow) }
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
                    CardMark(card: card, height: 18)
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

/// The sheet a transaction's detail has open: the editor Edit opens, Duplicate, Split, Enter amount, or what the Loan or
/// Debt and Reimbursement sections open. One at a time, so one `sheet` presents them all.
private enum TransactionDetailSheet: Hashable, Identifiable {
    case edit(TransactionEditFlow)
    case duplicate
    case split
    case enterAmount
    case loanOrDebt(LoanOrDebtAction)
    case reimbursement(ReimbursementAction)

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
