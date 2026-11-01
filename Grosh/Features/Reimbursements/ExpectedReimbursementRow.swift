import SwiftUI

/// An Expected reimbursement as Debts & Loans and the Home bell list it: who owes, for which Expense and when, its
/// reminder day, and what is outstanding (`?` for an open amount), or that it was paid back, closed or forgiven.
struct ExpectedReimbursementRow: View {
    let expectation: ExpectedReimbursement
    let today: CalendarDay

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: expectation.expense?.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(expectation.personName)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if expectation.isOpen, let due = expectation.reminderDay {
                    Text("\(Image(systemName: "bell")) Due \(due.date().formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(due <= today ? .red : .secondary)
                }
            }
            Spacer(minLength: 8)
            amount
        }
        .accessibilityElement(children: .combine)
    }

    /// "Owes me · Dinner · May 27, 2026".
    private var summary: String {
        let day = expectation.expense?.day.date().formatted(date: .abbreviated, time: .omitted) ?? ""
        return String(localized: "Owes me · \(expectation.expenseTitle) · \(day)")
    }

    @ViewBuilder
    private var amount: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch expectation.status {
            case .open:
                if let outstanding = expectation.outstanding, let expected = expectation.expected {
                    Text(outstanding.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    Text("of \(expected.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("?")
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    Text("Open amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .paidBack:
                Text(expectation.expected?.formatted() ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Settled")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .closed:
                Text(expectation.paid.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .forgiven:
                Text(expectation.expected?.formatted() ?? "?")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                ForgivenBadge()
            }
        }
    }
}

extension ExpectationTotals {
    /// What Debts & Loans heads the open expectations with: what is outstanding in each currency, and "+1 open" for the
    /// ones with no amount, which are left out of the figures. For example "$120.00 · +1 open".
    var summary: String {
        var parts = outstanding.map { $0.formatted() }
        if openAmountCount > 0 {
            parts.append(String(localized: "+\(openAmountCount) open"))
        }
        return parts.joined(separator: " · ")
    }
}
