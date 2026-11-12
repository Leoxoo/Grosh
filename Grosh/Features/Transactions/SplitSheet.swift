import SwiftData
import SwiftUI

/// Splits a transaction into parts. The transaction they came from is the first part and always shows what is left;
/// each part added takes its own amount, typed on the Keypad, category, date, note, With and Event, in the same wallet
/// and Card. Typing over the first part's amount changes the total, and the sheet then says how the wallet's balance
/// moves. Split makes the parts, which then show as Related transactions.
struct SplitSheet: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: SplitDraft
    /// The part the editor is open on, while it is open.
    @State private var editing: SplitPartRef?
    /// Whether the editor is open on a part about to be added.
    @State private var isAddingPart = false
    private var saver = SheetSaver(Strings.Transactions.couldntSplit)

    init(transaction: Transaction) {
        self.transaction = transaction
        _draft = State(initialValue: SplitDraft(splitting: transaction))
    }

    var body: some View {
        NavigationStack {
            List {
                totalSection

                Section(Strings.Transactions.thisTransaction) {
                    Button { editing = .original } label: {
                        SplitPartRow(part: draft.original)
                    }
                    .buttonStyle(.plain)
                }

                Section(Strings.Transactions.newParts) {
                    ForEach(draft.parts.indices, id: \.self) { index in
                        Button { editing = .part(index) } label: {
                            SplitPartRow(part: draft.parts[index])
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) {
                            draft.removePart(at: index)
                        }
                    }
                    Button(Strings.Transactions.addPart, systemImage: "plus") { isAddingPart = true }
                }

                if !draft.reimbursements.isEmpty {
                    reimbursementsSection
                }
            }
            .navigationTitle(Strings.Transactions.split)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Transactions.split) {
                        saver.save("Splitting a transaction") { try transaction.split(draft, in: context) }
                    }
                        .disabled(!draft.canSplit)
                }
            }
        }
        .macSheetSize(.list)
        .sheet(item: $editing) { part in
            editor(for: part)
        }
        .sheet(isPresented: $isAddingPart) {
            SplitPartEditor(
                title: Strings.Transactions.newPart, part: draft.newPart(), type: draft.partType, capacity: draft.capacity(of: nil)
            ) {
                draft.addPart($0)
            }
        }
        .failureAlert(saver)
    }

    /// The total the parts come to, and how the wallet's balance moves when it differs from the original amount.
    private var totalSection: some View {
        Section {
            LabeledContent(Strings.Common.total) {
                if draft.total == draft.was {
                    Text(draft.total.formatted())
                } else {
                    Text(Strings.Transactions.totalWas(draft.total.formatted(), draft.was.formatted()))
                }
            }
            .monospacedDigit()
            if draft.walletChange.cents != 0 {
                LabeledContent(Strings.Transactions.balanceChange) {
                    AmountText(amount: draft.walletChange, showsPlusSign: true)
                }
            }
        } footer: {
            if draft.leavesNothingOnOriginal {
                Text(Strings.Transactions.leaveSomeFooter)
            } else if draft.walletChange.cents != 0, let wallet = transaction.wallet {
                Text(Strings.Transactions.walletBalanceChanges(wallet.name))
            } else {
                Text(Strings.Transactions.originalShowsRestFooter)
            }
        }
    }

    /// Each Reimbursement of the transaction with a picker for the part it goes to; Split waits until all are chosen.
    private var reimbursementsSection: some View {
        Section {
            ForEach(draft.reimbursements.indices, id: \.self) { index in
                let reimbursement = draft.reimbursements[index].reimbursement
                Picker(selection: $draft.reimbursements[index].part) {
                    Text(Strings.Transactions.chooseAPart).tag(SplitPartRef?.none)
                    Text(Strings.Transactions.thisTransaction).tag(SplitPartRef?.some(.original))
                    ForEach(draft.parts.indices, id: \.self) { part in
                        Text(Strings.Transactions.partChoice(Category.name(of: draft.parts[part].category), draft.parts[part].amount.formatted()))
                            .tag(SplitPartRef?.some(.part(part)))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reimbursement.amount.formatted())
                            .monospacedDigit()
                        Text(reimbursement.day.shortText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(Strings.Common.reimbursements)
        } footer: {
            Text(Strings.Transactions.chooseReimbursementPartFooter)
        }
    }

    @ViewBuilder
    private func editor(for part: SplitPartRef) -> some View {
        switch part {
        case .original:
            SplitPartEditor(
                title: Strings.Transactions.thisTransactionTitle, part: draft.original, type: draft.partType,
                capacity: draft.capacity(of: part)
            ) {
                draft.original = $0
            }
        case .part(let index):
            SplitPartEditor(
                title: Strings.Transactions.editPart, part: draft.parts[index], type: draft.partType,
                capacity: draft.capacity(of: part)
            ) {
                draft.replacePart(at: index, with: $0)
            }
        }
    }

}

extension SplitPartRef: Identifiable {
    var id: Self { self }
}

/// A part with its category, date, note and amount. The amount is red while it is not above zero.
private struct SplitPartRow: View {
    let part: SplitPart

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: part.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(Category.name(of: part.category))
                    .lineLimit(1)
                Text(part.day.shortText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !part.note.isEmpty {
                    Text(part.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(part.amount.formatted())
                .monospacedDigit()
                .foregroundStyle(part.amount.cents > 0 ? MoneyDirection(category: part.category).tint : .invalid)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Edits one part of a split: its amount, typed on the Keypad, category, date, note, With and Event. Save hands the
/// part back to the split. `capacity` is how much the part could take before nothing is left on the transaction being
/// split, or `nil` for that transaction itself, whose amount changes the total instead.
private struct SplitPartEditor: View {
    let title: LocalizedStringResource
    let type: CategoryType
    let capacity: Money?
    let save: (SplitPart) -> Void

    @State private var part: SplitPart

    init(
        title: LocalizedStringResource, part: SplitPart, type: CategoryType, capacity: Money?,
        save: @escaping (SplitPart) -> Void
    ) {
        self.title = title
        self.type = type
        self.capacity = capacity
        self.save = save
        _part = State(initialValue: part)
    }

    var body: some View {
        KeypadSheet(
            title: Text(title), entry: $part.entry, canSave: part.isComplete,
            saving: "Keeping a part of a Split", failureTitle: Strings.Transactions.couldntSplit,
            save: { save(part) }
        ) { fields in
            Section {
                fields.amountRow(
                    Strings.Common.amount, currencyCode: part.currencyCode, tint: MoneyDirection(category: part.category).tint
                )
                CategoryPicker(title: Strings.Common.category, type: type, selection: $part.category)
                DayStepper(title: Strings.Common.date, day: $part.day)
                fields.noteField($part.note)
            } footer: {
                if let capacity {
                    Text(Strings.Transactions.leavesOnOriginal(part.leftOver(from: capacity).formatted()))
                } else {
                    Text(Strings.Transactions.differentAmountChangesTotal)
                }
            }

            Section {
                WithField(people: $part.people, picksOne: false)
                TextField(Strings.Common.event, text: $part.eventName)
                    .focused(fields.focus, equals: .event)
            }
        }
    }
}
