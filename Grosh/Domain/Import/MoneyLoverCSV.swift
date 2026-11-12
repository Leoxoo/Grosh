import Foundation

/// One transaction as a MoneyLover CSV export lists it.
nonisolated struct MoneyLoverRow: Equatable, Sendable {
    /// The line of the file the row starts on; the header is line 1.
    let line: Int
    let day: CalendarDay
    let categoryName: String
    /// Signed as MoneyLover shows it: negative takes money out of the wallet. Rounded to cents, in the currency of the
    /// row's `Currency` column.
    let amount: Money
    let walletName: String
    let note: String
    let withName: String
    let eventName: String
    let isExcludedFromReport: Bool
    /// The name of the row's Card, from a Grosh export's `Card` column: empty for no Card, `nil` when the file has no
    /// such column (``GroshCSVExport``).
    var cardName: String? = nil
    /// What links the row to the rows it is related to, from a Grosh export's `Linked` column: rows of one link share
    /// it. Empty for an unlinked row, `nil` when the file has no such column (``GroshCSVExport``).
    var link: String? = nil
    /// A forgiven Loan's or Debt's Forgiven mark, from a Grosh export's `Forgiven` columns: `nil` for none, or when
    /// the file has no such columns.
    var forgiven: Forgiven? = nil

    /// The Forgiven mark of a Loan or Debt in a Grosh export (ADR-0004).
    nonisolated struct Forgiven: Equatable, Sendable {
        /// What was forgiven, above zero.
        let amount: Money
        let day: CalendarDay
        /// The category the forgiven amount counts under; empty when the file names none.
        let categoryName: String
        let note: String
    }
}

/// A MoneyLover CSV export as ``MoneyLoverCSV/read(_:currencyCode:)`` reads it: its rows, in the order the file lists
/// them, and whether it is a Grosh export (``GroshCSVExport``), which the import restores as it was.
nonisolated struct MoneyLoverExport: Equatable, Sendable {
    let rows: [MoneyLoverRow]
    /// Whether the file has a Grosh export's `Card` and `Linked` columns (``GroshCSVFormat/isGroshExport(_:)``).
    let isGroshExport: Bool
}

/// Why a file can't be imported from MoneyLover. Nothing is replaced when it can't.
nonisolated enum MoneyLoverImportError: RuleRefusal, Equatable {
    /// The file doesn't have a MoneyLover export's Date, Category, Amount and Wallet columns.
    case notAMoneyLoverExport
    /// The file has the columns but not a single transaction.
    case noTransactions
    /// The row starting on `line` of the file (the header is line 1) has no valid date, amount, category or wallet.
    case unreadableRow(line: Int)
}

extension MoneyLoverImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notAMoneyLoverExport:
            String(localized: Strings.ImportExport.notAMoneyLoverExport)
        case .noTransactions:
            String(localized: Strings.ImportExport.noTransactionsInFile)
        case .unreadableRow(let line):
            String(localized: Strings.ImportExport.invalidLine(line))
        }
    }
}

/// Reads a MoneyLover CSV export, `Id, Date (MM/DD/YYYY), Category, Amount, Currency, Wallet, Note, With, Event,
/// Exclude from report, Members`, and a Grosh export's own columns, in the file format both share
/// (``GroshCSVFormat``). Columns are found by their header, so their order doesn't matter.
nonisolated enum MoneyLoverCSV {
    /// The export `text` holds, each amount in the currency its row's `Currency` column names, or in `currencyCode`,
    /// the one Settings → Currency names, for a row that names none. Throws ``MoneyLoverImportError`` for a file that
    /// isn't a MoneyLover export or has a row that can't be read.
    static func read(_ text: String, currencyCode: String) throws -> MoneyLoverExport {
        var records = GroshCSVFormat.records(in: text)
        guard !records.isEmpty else { throw MoneyLoverImportError.notAMoneyLoverExport }
        let columns = try Columns(header: records.removeFirst().fields, currencyCode: currencyCode)
        guard !records.isEmpty else { throw MoneyLoverImportError.noTransactions }
        let rows = try records.map { record in
            guard let row = columns.row(from: record.fields, line: record.line) else {
                throw MoneyLoverImportError.unreadableRow(line: record.line)
            }
            return row
        }
        return MoneyLoverExport(rows: rows, isGroshExport: columns.isGroshExport)
    }

    /// Where each column sits in a row, found by its header.
    private struct Columns {
        typealias Column = GroshCSVFormat.Column

        private let positions: [Column: Int]
        let isGroshExport: Bool
        /// The currency of a row whose `Currency` column is empty, or of every row when the file has none.
        let currencyCode: String

        init(header: [String], currencyCode: String) throws {
            let positions = GroshCSVFormat.positions(inHeader: header)
            guard [Column.date, .category, .amount, .wallet].allSatisfy({ positions[$0] != nil }) else {
                throw MoneyLoverImportError.notAMoneyLoverExport
            }
            self.positions = positions
            self.currencyCode = currencyCode
            isGroshExport = GroshCSVFormat.isGroshExport(positions)
        }

        /// The row `fields` hold, or `nil` when its date, amount, category or wallet (or a Forgiven mark's amount or
        /// date) can't be read. Columns missing at the end of the row are empty. The notes are kept as written; every
        /// other field loses the spaces and line breaks around it.
        func row(from fields: [String], line: Int) -> MoneyLoverRow? {
            func written(_ column: Column) -> String {
                guard let index = positions[column], fields.indices.contains(index) else { return "" }
                return fields[index]
            }
            func field(_ column: Column) -> String {
                written(column).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // A Grosh export's own column, `nil` when the file has none.
            func groshField(_ column: Column) -> String? {
                positions[column] == nil ? nil : field(column)
            }
            let categoryName = field(.category)
            let walletName = field(.wallet)
            let currency = field(.currency).isEmpty ? currencyCode : field(.currency).uppercased()
            guard let day = GroshCSVFormat.day(from: field(.date)),
                  let amount = Money(decimalString: field(.amount), currencyCode: currency),
                  !categoryName.isEmpty, !walletName.isEmpty
            else { return nil }
            var forgivenMark: MoneyLoverRow.Forgiven?
            if !field(.forgiven).isEmpty {
                guard let forgivenAmount = Money(decimalString: field(.forgiven), currencyCode: currency),
                      let forgivenDay = GroshCSVFormat.day(from: field(.forgivenDate))
                else { return nil }
                forgivenMark = MoneyLoverRow.Forgiven(
                    amount: forgivenAmount, day: forgivenDay, categoryName: field(.forgivenCategory),
                    note: written(.forgivenNote)
                )
            }
            return MoneyLoverRow(
                line: line,
                day: day,
                categoryName: categoryName,
                amount: amount,
                walletName: walletName,
                note: written(.note),
                withName: field(.with),
                eventName: field(.event),
                isExcludedFromReport: !field(.excludeFromReport).isEmpty,
                cardName: groshField(.card),
                link: groshField(.linked),
                forgiven: forgivenMark
            )
        }
    }
}
