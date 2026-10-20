import SwiftData
import SwiftUI

/// What the Reimbursement section of the transaction detail opens.
enum ReimbursementAction: Hashable, Identifiable {
    case paidBack, moveIn
    case edit(Reimbursement)

    var id: Self { self }
}

/// The transaction detail's section for an Expense: each Reimbursement with its day and note, opening its sheet to edit
/// and deleted by swipe or from its menu, then Someone paid me back and Move an existing transaction in. Shows nothing
/// for any other transaction. Use inside a `List`, with ``SwiftUI/View/reimbursementSheets(for:action:)`` on the screen
/// to present what `action` opens.
struct ReimbursementSection: View {
    let transaction: Transaction
    @Binding var action: ReimbursementAction?

    @State private var errorMessage: String?

    var body: some View {
        if transaction.canBeReimbursed {
            Section {
                ForEach(transaction.orderedReimbursements) { entry in
                    Button {
                        action = .edit(entry)
                    } label: {
                        ReimbursementRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { delete(entry) }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { action = .edit(entry) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                    }
                }
                Button("Someone paid me back", systemImage: "plus.circle") { action = .paidBack }
                Button("Move an existing transaction in", systemImage: "arrow.down.circle") { action = .moveIn }
            } header: {
                Text("Reimbursements")
            } footer: {
                Text("Money paid back is kept on this expense. Its net, what is left of it, is what counts in your balance and reports.")
            }
            .errorAlert("Couldn't Delete Reimbursement", message: $errorMessage)
        }
    }

    private func delete(_ entry: Reimbursement) {
        do {
            try entry.delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One Reimbursement: the day and note on the left, the amount paid back on the right.
private struct ReimbursementRow: View {
    let entry: Reimbursement

    var body: some View {
        LabeledContent {
            AmountText(amount: entry.amount, showsPlusSign: true)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.day.date().formatted(date: .abbreviated, time: .omitted))
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Presents Someone paid me back, Move an existing transaction in or an entry's edit sheet for `transaction` while
    /// `action` says which. Attach to the screen, outside its `List`, so presenting doesn't depend on the list's rows.
    func reimbursementSheets(for transaction: Transaction, action: Binding<ReimbursementAction?>) -> some View {
        sheet(item: action) { action in
            switch action {
            case .paidBack: ReimbursementEditor(expense: transaction)
            case .moveIn: ReimbursementMoveInPicker(expense: transaction)
            case .edit(let entry): ReimbursementEditor(expense: transaction, editing: entry)
            }
        }
    }
}

/// What the Reimbursements of an Expense leave of it, shown as `= −$20` beside its original amount: green when it was
/// paid back more than it cost. In the Total (`listed`) it also takes off what was paid back into other wallets there
/// (ADR-0010). Shows nothing for a transaction without Reimbursements.
struct ReimbursementNetText: View {
    let transaction: Transaction
    var listed = ListedAmount.net

    var body: some View {
        // Read from the stored figures first, so a row that was never paid back reads nothing else.
        if transaction.reimbursedCents > 0 || (listed == .netInTotal && transaction.hasPaybacksElsewhere) {
            let net = listed == .netInTotal ? transaction.totalViewNet : transaction.net
            if net.cents != transaction.amountCents {
                Text(verbatim: "= " + net.signedFormatted())
                    .monospacedDigit()
                    .foregroundStyle(net.cents > 0 ? net.tint : .secondary)
            }
        }
    }
}

/// An Expense's Reimbursements as its row lists them under the title: `+20, +10, +3`. They are cut with "…" only when
/// they don't fit. In a wallet's own list (not the Total) it adds what was paid back into other wallets: `+20 to Cash`
/// (ADR-0010). Shows nothing for a transaction without Reimbursements.
struct ReimbursementEntriesText: View {
    let transaction: Transaction
    var listed = ListedAmount.net

    var body: some View {
        // Read from the stored figures first, so a row without Reimbursements never reads them.
        let summary = transaction.reimbursedCents > 0 ? transaction.reimbursementSummary() : ""
        let elsewhere = listed == .net && transaction.hasPaybacksElsewhere ? transaction.elsewhereSummary() : ""
        let text = [summary, elsewhere].filter { !$0.isEmpty }.joined(separator: ", ")
        if !text.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
