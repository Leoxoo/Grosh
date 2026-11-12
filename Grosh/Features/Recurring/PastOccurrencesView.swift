import SwiftData
import SwiftUI

/// The start-date prompt: the occurrences from a schedule's start day through today, each with a plus to pick it.
/// Picking makes nothing until Save, and Save makes only the picked days. With none picked, Save makes nothing and
/// closes, and the schedule stays as it was saved. A day left out is never made.
struct PastOccurrencesView: View {
    let recurring: RecurringTransaction
    /// The days offered, in order.
    let days: [CalendarDay]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selected: Set<CalendarDay> = []
    private var saver = SheetSaver(Strings.Recurring.couldntAddTransactions, log: Log.recurring)

    init(recurring: RecurringTransaction, days: [CalendarDay]) {
        self.recurring = recurring
        self.days = days
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(days, id: \.self) { day in
                        row(day)
                    }
                } footer: {
                    Text(Strings.Recurring.pastOccurrencesFooter)
                }
            }
            .navigationTitle(Strings.Recurring.pastOccurrences)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(Strings.Recurring.addAll) { selected = Set(days) }
                        .disabled(selected.count == days.count)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.save, action: save)
                }
            }
        }
        .failureAlert(saver)
    }

    private func row(_ day: CalendarDay) -> some View {
        let isSelected = selected.contains(day)
        return Button {
            if isSelected {
                selected.remove(day)
            } else {
                selected.insert(day)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "plus.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(day.date(), style: .date)
                Spacer(minLength: 8)
                if recurring.estimatesAmount {
                    EstimatedBadge()
                }
                AmountText(amount: recurring.startingAmount)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        saver.save("Making transactions for past days") {
            try recurring.makeTransactions(on: days.filter { selected.contains($0) }, in: context)
        }
    }
}
