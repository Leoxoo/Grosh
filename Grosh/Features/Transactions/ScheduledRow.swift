import SwiftUI

/// A Scheduled row in Future: an upcoming occurrence of a Recurring transaction, labelled Scheduled, with its name,
/// signed amount and date. It is read-only: tapping it opens the Recurring transaction, not a transaction editor.
struct ScheduledRow: View {
    let occurrence: ScheduledOccurrence

    /// The due day, such as "Mon, Oct 12, 2026".
    private var dayText: String {
        occurrence.day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: occurrence.recurring.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.recurring.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ScheduledBadge()
                    Text(dayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                AmountText(amount: occurrence.amount)
                HStack(spacing: 6) {
                    if occurrence.isEstimated {
                        EstimatedBadge()
                    }
                    if let wallet = occurrence.recurring.wallet {
                        Image(systemName: wallet.symbolName)
                            .font(.caption)
                            .foregroundStyle(wallet.color.color)
                            .accessibilityLabel(wallet.name)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A small capsule saying a row is a Scheduled occurrence, not a transaction yet.
struct ScheduledBadge: View {
    var body: some View {
        Label("Scheduled", systemImage: "calendar.badge.clock")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}
