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
    @State private var errorMessage: String?

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
                    Button(Strings.Transactions.split, action: split)
                        .disabled(!draft.canSplit)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
        #endif
        .sheet(item: $editing) { part in
            editor(for: part)
        }
        .sheet(isPresented: $isAddingPart) {
            SplitPartEditor(
                title: Strings.Transactions.newPart, part: draft.newPart(), type: partType, capacity: draft.original.amount.cents
            ) {
                draft.addPart($0)
            }
        }
        .errorAlert(Strings.Transactions.couldntSplit, message: $errorMessage)
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
            if draft.original.amount.cents <= 0 {
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
                        Text("\(draft.parts[part].categoryName), \(draft.parts[part].amount.formatted())")
                            .tag(SplitPartRef?.some(.part(part)))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reimbursement.amount.formatted())
                            .monospacedDigit()
                        Text(reimbursement.day.date().formatted(date: .abbreviated, time: .omitted))
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

    /// The type every part's category is of: the transaction's own.
    private var partType: CategoryType { transaction.category?.type ?? .expense }

    @ViewBuilder
    private func editor(for part: SplitPartRef) -> some View {
        switch part {
        case .original:
            SplitPartEditor(title: Strings.Transactions.thisTransactionTitle, part: draft.original, type: partType, capacity: nil) {
                draft.original = $0
            }
        case .part(let index):
            SplitPartEditor(
                title: Strings.Transactions.editPart, part: draft.parts[index], type: partType,
                capacity: draft.original.amount.cents + draft.parts[index].amount.cents
            ) {
                draft.replacePart(at: index, with: $0)
            }
        }
    }

    private func split() {
        do {
            try transaction.split(draft, in: context)
            dismiss()
        } catch {
            Log.store.failed("Splitting a transaction", error)
            errorMessage = error.localizedDescription
        }
    }
}

extension SplitPartRef: Identifiable {
    var id: Self { self }
}

private extension SplitPart {
    /// The category's name, or "Uncategorized" before one is chosen, as a transaction's row names it.
    var categoryName: String { Category.name(of: category) }
}

/// A part with its category, date, note and amount. The amount is red while it is not above zero.
private struct SplitPartRow: View {
    let part: SplitPart

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: part.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.categoryName)
                    .lineLimit(1)
                Text(part.day.date().formatted(date: .abbreviated, time: .omitted))
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
                .foregroundStyle(part.amount.cents > 0 ? Money(cents: part.category?.sign ?? 0).tint : .invalid)
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
    let capacity: Int?
    let save: (SplitPart) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var part: SplitPart
    @State private var entry: AmountEntry

    init(
        title: LocalizedStringResource, part: SplitPart, type: CategoryType, capacity: Int?,
        save: @escaping (SplitPart) -> Void
    ) {
        self.title = title
        self.type = type
        self.capacity = capacity
        self.save = save
        _part = State(initialValue: part)
        _entry = State(initialValue: AmountEntry(cents: part.amount.cents))
    }

    private var currencyCode: String { part.amount.currencyCode }

    /// What the keypad comes to, in cents.
    private var cents: Int { entry.cents ?? 0 }

    var body: some View {
        KeypadSheet(
            title: Text(title), entry: $entry, canSave: cents > 0 && part.category != nil, save: commit
        ) { fields in
            Section {
                fields.amountRow(Strings.Common.amount, currencyCode: currencyCode, tint: Money(cents: part.category?.sign ?? 0).tint)
                CategoryPicker(title: Strings.Common.category, type: type, selection: $part.category)
                DayStepper(title: Strings.Common.date, day: $part.day)
                fields.noteField($part.note)
            } footer: {
                if let capacity {
                    Text(Strings.Transactions.leavesOnOriginal(Money(cents: capacity - cents, currencyCode: currencyCode).formatted()))
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

    private func commit() {
        var result = part
        result.amount = Money(cents: cents, currencyCode: currencyCode)
        save(result)
        dismiss()
    }
}
