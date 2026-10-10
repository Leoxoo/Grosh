import Foundation

/// One transaction as a MoneyLover CSV export lists it.
nonisolated struct MoneyLoverRow: Equatable, Sendable {
    /// The line of the file the row starts on; the header is line 1.
    let line: Int
    let day: CalendarDay
    let categoryName: String
    /// Signed as MoneyLover shows it: negative takes money out of the wallet. Rounded to cents.
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

    /// Whether the row comes from a Grosh export, which names each row's Card and links rather than leaving the
    /// import to work them out.
    var isFromGroshExport: Bool { cardName != nil && link != nil }
}

/// Why a file can't be imported from MoneyLover. Nothing is replaced when it can't.
nonisolated enum MoneyLoverImportError: Error, Equatable {
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
            String(localized: "This isn't a MoneyLover CSV export. It needs Date, Category, Amount and Wallet columns.")
        case .noTransactions:
            String(localized: "This file has no transactions.")
        case .unreadableRow(let line):
            String(localized: "Line \(line) of the file has no valid date, amount, category or wallet.")
        }
    }
}

/// Reads a MoneyLover CSV export: `Id, Date (MM/DD/YYYY), Category, Amount, Currency, Wallet, Note, With, Event,
/// Exclude from report, Members`, and a Grosh export's `Card` and `Linked` columns (``GroshCSVExport``). Columns are
/// found by their header, so their order doesn't matter.
nonisolated enum MoneyLoverCSV {
    /// The export's rows, in the order the file lists them. Throws ``MoneyLoverImportError`` for a file that isn't
    /// a MoneyLover export or has a row that can't be read.
    static func rows(in text: String) throws -> [MoneyLoverRow] {
        var records = Self.records(in: text)
        guard !records.isEmpty else { throw MoneyLoverImportError.notAMoneyLoverExport }
        let columns = try Columns(header: records.removeFirst().fields)
        guard !records.isEmpty else { throw MoneyLoverImportError.noTransactions }
        return try records.map { record in
            guard let row = columns.row(from: record.fields, line: record.line) else {
                throw MoneyLoverImportError.unreadableRow(line: record.line)
            }
            return row
        }
    }

    /// Where each column sits in a row, found by its header.
    private struct Columns {
        let date: Int, category: Int, amount: Int, wallet: Int
        let note: Int?, with: Int?, event: Int?, excluded: Int?, card: Int?, linked: Int?

        init(header: [String]) throws {
            let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            func index(_ name: String) -> Int? { names.firstIndex(of: name) }
            guard let date = index("date"), let category = index("category"), let amount = index("amount"),
                  let wallet = index("wallet")
            else { throw MoneyLoverImportError.notAMoneyLoverExport }
            self.date = date
            self.category = category
            self.amount = amount
            self.wallet = wallet
            note = index("note")
            with = index("with")
            event = index("event")
            excluded = index("exclude from report")
            card = index("card")
            linked = index("linked")
        }

        /// The row `fields` hold, or `nil` when its date, amount, category or wallet can't be read. Columns missing
        /// at the end of the row are empty. The note is kept as written; every other field loses the spaces and line
        /// breaks around it.
        func row(from fields: [String], line: Int) -> MoneyLoverRow? {
            func written(_ index: Int?) -> String {
                guard let index, fields.indices.contains(index) else { return "" }
                return fields[index]
            }
            func field(_ index: Int?) -> String {
                written(index).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let categoryName = field(category)
            let walletName = field(wallet)
            guard let day = MoneyLoverCSV.day(from: field(date)), let amount = Money(decimalString: field(amount)),
                  !categoryName.isEmpty, !walletName.isEmpty
            else { return nil }
            return MoneyLoverRow(
                line: line,
                day: day,
                categoryName: categoryName,
                amount: amount,
                walletName: walletName,
                note: written(note),
                withName: field(with),
                eventName: field(event),
                isExcludedFromReport: !field(excluded).isEmpty,
                cardName: card.map { field($0) },
                link: linked.map { field($0) }
            )
        }
    }

    /// The day a MoneyLover date such as `01/31/2026` (month first) names, or `nil` for anything else.
    private static func day(from text: String) -> CalendarDay? {
        guard let match = text.wholeMatch(of: #/([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})/#),
            let month = Int(match.1), let day = Int(match.2), let year = Int(match.3),
            (1...12).contains(month),
            (1...CalendarMonth(year: year, month: month).dayCount).contains(day)
        else { return nil }
        return CalendarDay(year: year, month: month, day: day)
    }

    /// One record of a CSV file: its fields, and the line of the file it starts on.
    struct Record {
        /// The header is line 1.
        let line: Int
        let fields: [String]
    }

    /// Splits CSV text into records. A field in double quotes may hold commas, line breaks and doubled quotes
    /// (`""` for one `"`). Blank lines are skipped.
    static func records(in text: String) -> [Record] {
        enum State { case fieldStart, unquoted, quoted, quoteInQuoted }
        var records: [Record] = []
        var record: [String] = []
        var field = ""
        var state = State.fieldStart
        var line = 1
        var recordLine = 1

        func endField() {
            record.append(field)
            field = ""
            state = .fieldStart
        }
        func endRecord() {
            if state != .fieldStart || !record.isEmpty || !field.isEmpty {
                endField()
                records.append(Record(line: recordLine, fields: record))
            }
            record = []
            state = .fieldStart
        }

        for character in text.drop(while: { $0 == "\u{FEFF}" }) {
            switch state {
            case .quoted:
                if character == "\"" { state = .quoteInQuoted } else { field.append(character) }
            case .quoteInQuoted where character == "\"":
                field.append(character)
                state = .quoted
            case .fieldStart where character == "\"":
                state = .quoted
            case .fieldStart, .unquoted, .quoteInQuoted:
                if character == "," {
                    endField()
                } else if character.isNewline {
                    endRecord()
                } else {
                    field.append(character)
                    state = .unquoted
                }
            }
            if character.isNewline {
                line += 1
                if state == .fieldStart, record.isEmpty { recordLine = line }
            }
        }
        endRecord()
        return records
    }
}
