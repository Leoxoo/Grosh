import Foundation
import SwiftData

/// Account → Export CSV: every transaction, written as a MoneyLover CSV export lists it, plus a `Card` column naming
/// its Card and a `Linked` column that related rows share. Import from MoneyLover recognises the file by those two
/// columns and restores it with "Replace all data" (``MoneyLoverImport``): exporting what it restored gives the same
/// file again.
enum GroshCSVExport {
    /// MoneyLover's columns, then Grosh's own.
    static let header = [
        "Id", "Date", "Category", "Amount", "Currency", "Wallet", "Note", "With", "Event", "Exclude from report",
        "Members", "Card", "Linked",
    ]

    /// Every transaction in `context`, in list order.
    static func csv(in context: ModelContext) throws -> String {
        try csv(of: context.fetch(FetchDescriptor<Transaction>(sortBy: Transaction.listOrder)).inListOrder())
    }

    /// `transactions` in the order given, one row each, with MoneyLover's line endings. Rows are numbered from 1 in
    /// the `Id` column. Linked transactions share a number in the `Linked` column, numbered from 1 in the order the
    /// file first lists each link, so the same data always gives the same file. A transaction with no wallet or
    /// category has nothing to file it under, so it is left out.
    static func csv(of transactions: [Transaction]) -> String {
        var links: [UUID: Int] = [:]
        var lines = [header.map(field).joined(separator: ",")]
        for transaction in transactions {
            guard let wallet = transaction.wallet, let category = transaction.category else { continue }
            let link = transaction.linkID.map { id -> Int in
                if let number = links[id] { return number }
                let number = links.count + 1
                links[id] = number
                return number
            }
            let day = transaction.day
            let row = [
                String(lines.count),
                String(format: "%02d/%02d/%04d", day.month, day.day, day.year),
                category.name,
                Money(cents: transaction.amountCents).decimalString,
                wallet.currencyCode,
                wallet.name,
                transaction.note,
                transaction.withName,
                transaction.eventName,
                transaction.isExcludedFromReport ? "1" : "",
                "",
                transaction.card?.name ?? "",
                link.map { String($0) } ?? "",
            ]
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.map { $0 + "\r\n" }.joined()
    }

    /// The name the file is shared under when exported on `day`, such as `Grosh 2026-10-10.csv`.
    static func fileName(on day: CalendarDay) -> String {
        String(format: "Grosh %04d-%02d-%02d.csv", day.year, day.month, day.day)
    }

    /// `text` as one CSV field: in double quotes, with its quotes doubled, when it holds a comma, a quote or a line
    /// break; as it is otherwise.
    private static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
