import Foundation
import SwiftData

/// Account → Export CSV: every transaction, written as a MoneyLover CSV export lists it, plus a `Card` column naming
/// its Card, a `Linked` column that related rows share, and on a forgiven Loan or Debt its Forgiven mark: the amount,
/// date, category and note; on a part of a Split a `Split from` column, the `Id` of the row it was split from; and on an
/// Expense with Reimbursements a `Reimbursement` column listing them as `amount day`, earliest day first and separated
/// by `; `, such as `20.00 10/06/2026; 10.00 10/08/2026` (an entry's note is not written). The `With` column names the
/// people in With, by name and separated by `; ` (``Transaction/withName``). The columns, dates and quoting are
/// ``GroshCSVFormat``'s. Import from MoneyLover recognises the file by the `Card` and `Linked` columns and restores it
/// with "Replace all data" (``MoneyLoverImport``): exporting what it restored gives the same file again. The
/// `Split from` and `Reimbursement` columns are written for the record; import ignores them.
enum GroshCSVExport {

    /// Every transaction in `context` outside Recently Deleted, in list order.
    static func csv(in context: ModelContext) throws -> String {
        var descriptor = Transaction.notDeleted
        descriptor.sortBy = Transaction.listOrder
        return try csv(of: context.fetch(descriptor).inListOrder())
    }

    /// `transactions` in the order given, one row each, with MoneyLover's line endings. Rows are numbered from 1 in
    /// the `Id` column. Linked transactions share a number in the `Linked` column, numbered from 1 in the order the
    /// file first lists each link, so the same data always gives the same file. A transaction with no wallet or
    /// category has nothing to file it under, so it is left out. A part of a Split names the row of the Split's
    /// original, its oldest part (`splitOriginal`), in `Split from`; the original itself leaves it
    /// empty.
    static func csv(of transactions: [Transaction]) -> String {
        let filed = transactions.filter { $0.wallet != nil && $0.category != nil }
        var partsByLink: [UUID: [Transaction]] = [:]
        for transaction in filed where transaction.isSplitPart {
            if let link = transaction.linkID { partsByLink[link, default: []].append(transaction) }
        }
        let rowNumbers = Dictionary(uniqueKeysWithValues: filed.enumerated().map { (ObjectIdentifier($1), $0 + 1) })
        let originals = partsByLink.compactMapValues { parts in
            parts.splitOriginal.flatMap { rowNumbers[ObjectIdentifier($0)] }
        }
        var links: [UUID: Int] = [:]
        var lines = [GroshCSVFormat.line(GroshCSVFormat.columns.map(\.rawValue))]
        for transaction in filed {
            guard let wallet = transaction.wallet, let category = transaction.category else { continue }
            let link = transaction.linkID.map { id -> Int in
                if let number = links[id] { return number }
                let number = links.count + 1
                links[id] = number
                return number
            }
            let day = transaction.day
            let forgiveness = transaction.forgiveness
            let original: Int? = transaction.linkID.flatMap { originals[$0] }
            let splitFrom: String = original.map { $0 == lines.count ? "" : String($0) } ?? ""
            let reimbursement: String = transaction.orderedReimbursements
                .map { "\($0.amount.decimalString) \(GroshCSVFormat.date($0.day))" }
                .joined(separator: "; ")
            // In the order of `GroshCSVFormat.columns`.
            let row = [
                String(lines.count),
                GroshCSVFormat.date(day),
                category.name,
                transaction.amount.decimalString,
                wallet.currencyCode,
                wallet.name,
                transaction.note,
                transaction.withName,
                transaction.eventName,
                transaction.isExcludedFromReport ? "1" : "",
                "",
                transaction.card?.name ?? "",
                link.map { String($0) } ?? "",
                forgiveness.map { $0.amount.decimalString } ?? "",
                forgiveness.map { GroshCSVFormat.date($0.day) } ?? "",
                forgiveness?.category?.name ?? "",
                forgiveness?.note ?? "",
                splitFrom,
                reimbursement,
            ]
            lines.append(GroshCSVFormat.line(row))
        }
        return lines.joined()
    }

    /// The name the file is shared under when exported on `day`, such as `Grosh 2026-10-10.csv`.
    static func fileName(on day: CalendarDay) -> String {
        String(format: "Grosh %04d-%02d-%02d.csv", day.year, day.month, day.day)
    }
}
