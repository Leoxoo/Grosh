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
    @State private var editing: SplitTarget?
    @State private var errorMessage: String?

    init(transaction: Transaction) {
        self.transaction = transaction
        _draft = State(initialValue: SplitDraft(splitting: transaction))
    }

    var body: some View {
        NavigationStack {
            List {
                totalSection

                Section("This transaction") {
                    Button { editing = .original } label: {
                        SplitPartRow(part: draft.original)
                    }
                    .buttonStyle(.plain)
                }

                Section("New parts") {
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
                    Button("Add Part", systemImage: "plus") { editing = .new }
                }

                if !draft.reimbursements.isEmpty {
                    reimbursementsSection
                }
            }
            .navigationTitle("Split")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split", action: split)
                        .disabled(!draft.canSplit)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
        #endif
        .sheet(item: $editing) { target in
            editor(for: target)
        }
        .errorAlert("Couldn't Split Transaction", message: $errorMessage)
    }

    /// The total the parts come to, and how the wallet's balance moves when it differs from the original amount.
    private var totalSection: some View {
        Section {
            LabeledContent("Total") {
                if draft.total == draft.was {
                    Text(draft.total.formatted())
                } else {
                    Text("\(draft.total.formatted()) (was \(draft.was.formatted()))")
                }
            }
            .monospacedDigit()
            if draft.walletChange.cents != 0 {
                LabeledContent("Balance change") {
                    AmountText(amount: draft.walletChange, showsPlusSign: true)
                }
            }
        } footer: {
            if draft.original.amount.cents <= 0 {
                Text("Leave some on this transaction, or type over its amount to raise the total.")
            } else if draft.walletChange.cents != 0, let wallet = transaction.wallet {
                Text("\(wallet.name)'s balance changes by the difference.")
            } else {
                Text("This transaction shows what the other parts leave of the total.")
            }
        }
    }

    /// Each Reimbursement of the transaction with a picker for the part it goes to; Split waits until all are chosen.
    private var reimbursementsSection: some View {
        Section {
            ForEach(draft.reimbursements.indices, id: \.self) { index in
                let reimbursement = draft.reimbursements[index].reimbursement
                Picker(selection: $draft.reimbursements[index].part) {
                    Text("Choose a part").tag(SplitPartRef?.none)
                    Text("This transaction").tag(SplitPartRef?.some(.original))
                    ForEach(draft.parts.indices, id: \.self) { part in
                        Text("\(draft.parts[part].category?.name ?? String(localized: "Uncategorized")), \(draft.parts[part].amount.formatted())")
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
            Text("Reimbursements")
        } footer: {
            Text("Choose the part each Reimbursement was paid back against.")
        }
    }

    @ViewBuilder
    private func editor(for target: SplitTarget) -> some View {
        let type = transaction.category?.type ?? .expense
        switch target {
        case .original:
            SplitPartEditor(title: "This Transaction", part: draft.original, type: type, capacity: nil) {
                draft.original = $0
            }
        case .new:
            SplitPartEditor(
                title: "New Part", part: draft.newPart(), type: type, capacity: draft.original.amount.cents
            ) {
                draft.addPart($0)
            }
        case .part(let index):
            SplitPartEditor(
                title: "Edit Part", part: draft.parts[index], type: type,
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
            errorMessage = error.localizedDescription
        }
    }
}

/// Which part of the split the editor is open on.
private enum SplitTarget: Hashable, Identifiable {
    /// The transaction being split, which keeps what the other parts leave.
    case original
    /// A part about to be added.
    case new
    /// The added part at this index.
    case part(Int)

    var id: Self { self }
}

/// A part with its category, date, note and amount. The amount is red while it is not above zero.
private struct SplitPartRow: View {
    let part: SplitPart

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: part.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.category?.name ?? String(localized: "Uncategorized"))
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
                .foregroundStyle(part.amount.cents > 0 ? Money(cents: part.category?.sign ?? 0).tint : .red)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Edits one part of a split: its amount, typed on the Keypad, category, date, note, With and Event. Save hands the
/// part back to the split. `capacity` is how much the part could take before nothing is left on the transaction being
/// split, or `nil` for that transaction itself, whose amount changes the total instead.
private struct SplitPartEditor: View {
    let title: LocalizedStringKey
    let type: CategoryType
    let capacity: Int?
    let save: (SplitPart) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var part: SplitPart
    @State private var entry: AmountEntry

    init(
        title: LocalizedStringKey, part: SplitPart, type: CategoryType, capacity: Int?,
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
                fields.amountRow("Amount", currencyCode: currencyCode, tint: Money(cents: part.category?.sign ?? 0).tint)
                CategoryPicker(title: "Category", type: type, selection: $part.category)
                DayStepper(title: "Date", day: $part.day)
                fields.noteField($part.note)
            } footer: {
                if let capacity {
                    Text("Leaves \(Money(cents: capacity - cents, currencyCode: currencyCode).formatted()) on the transaction being split.")
                } else {
                    Text("Typing a different amount changes the total.")
                }
            }

            Section {
                TextField("With", text: $part.withName)
                    .focused(fields.focus, equals: .withName)
                if fields.focus.wrappedValue == .withName {
                    WithNameSuggestions(typed: part.withName) { name in
                        part.withName = name
                        fields.focus.wrappedValue = nil
                    }
                }
                TextField("Event", text: $part.eventName)
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
