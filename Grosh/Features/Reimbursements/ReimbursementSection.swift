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
                        Button(Strings.Common.delete, role: .destructive) { delete(entry) }
                    }
                    .contextMenu {
                        Button(Strings.Common.edit, systemImage: "pencil") { action = .edit(entry) }
                        Button(Strings.Common.delete, systemImage: "trash", role: .destructive) { delete(entry) }
                    }
                }
                Button(Strings.Reimbursements.someonePaidMeBack, systemImage: "plus.circle") { action = .paidBack }
                Button(Strings.Reimbursements.moveExistingIn, systemImage: "arrow.down.circle") { action = .moveIn }
            } header: {
                Text(Strings.Common.reimbursements)
            } footer: {
                Text(Strings.Reimbursements.sectionFooter)
            }
            .errorAlert(Strings.Reimbursements.couldntDelete, message: $errorMessage)
        }
    }

    private func delete(_ entry: Reimbursement) {
        do {
            try entry.delete()
        } catch {
            Log.store.failed("Deleting a Reimbursement", error)
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
/// paid back more than it cost. Shows nothing for a transaction without Reimbursements.
struct ReimbursementNetText: View {
    let transaction: Transaction

    var body: some View {
        if transaction.reimbursedCents > 0 {
            Text(verbatim: "= " + transaction.net.signedFormatted())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(transaction.netCents > 0 ? transaction.net.tint : .secondary)
        }
    }
}

/// An Expense's Reimbursements as its row lists them under the title: `+20, +10, +3`. They are cut with "…" only when
/// they don't fit. Shows nothing for a transaction without Reimbursements.
struct ReimbursementEntriesText: View {
    let transaction: Transaction

    var body: some View {
        // Read from the stored total first, so a row without Reimbursements never reads them.
        let summary = transaction.reimbursedCents > 0 ? transaction.reimbursementSummary() : ""
        if !summary.isEmpty {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
