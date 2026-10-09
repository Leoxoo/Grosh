import SwiftUI

extension CardKind {
    var title: LocalizedStringKey {
        switch self {
        case .debit: "Debit"
        case .credit: "Credit"
        }
    }
}

extension Card {
    /// The name with the last 4 digits when known, e.g. "Apple Card ••4821".
    var displayName: String {
        guard let lastFourDigits else { return name }
        return "\(name) ••\(lastFourDigits)"
    }

    /// A day of the month as people say it: "1st", "22nd", "31st".
    static func ordinalDay(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: day as NSNumber) ?? "\(day)"
    }
}

/// A Card's icon, name, kind, paying wallet and statement date, as listed in Account → Cards.
struct CardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            SymbolCircle(symbolName: "creditcard.fill", color: card.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        var parts = [card.kind == .debit ? String(localized: "Debit") : String(localized: "Credit")]
        if let wallet = card.payingWallet {
            parts.append(wallet.name)
        }
        if let statementDay = card.statementDay {
            parts.append(String(localized: "Statement on the \(Card.ordinalDay(statementDay))"))
        }
        return parts.joined(separator: " · ")
    }
}
