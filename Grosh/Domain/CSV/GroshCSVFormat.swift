import Foundation

/// The CSV file Export CSV writes (``GroshCSVExport``) and Import from MoneyLover reads (``MoneyLoverCSV``): a MoneyLover
/// export's columns, then Grosh's own, its dates, its quoting and its line endings. Both go through this one type, so an
/// exported file reads back as it was written.
nonisolated enum GroshCSVFormat {
    /// A column, by the header that names it. A MoneyLover export has those up to ``members``; a Grosh export adds the
    /// rest.
    enum Column: String, CaseIterable, Sendable {
        case id = "Id"
        case date = "Date"
        case category = "Category"
        case amount = "Amount"
        case currency = "Currency"
        case wallet = "Wallet"
        case note = "Note"
        case with = "With"
        case event = "Event"
        case excludeFromReport = "Exclude from report"
        case members = "Members"
        /// The row's Card, by name.
        case card = "Card"
        /// A number related rows share.
        case linked = "Linked"
        case forgiven = "Forgiven"
        case forgivenDate = "Forgiven date"
        case forgivenCategory = "Forgiven category"
        case forgivenNote = "Forgiven note"
        /// On a part of a Split, the `Id` of the row it was split from. Written for the record; import ignores it.
        case splitFrom = "Split from"
        /// An Expense's Reimbursements. Written for the record; import ignores it.
        case reimbursement = "Reimbursement"
    }

    /// The columns in the order an export writes them: MoneyLover's, then Grosh's own.
    static let columns = Column.allCases

    /// Where each column of `header` sits, found by its name ignoring case and the spaces around it, so their order
    /// doesn't matter.
    static func positions(inHeader header: [String]) -> [Column: Int] {
        var positions: [Column: Int] = [:]
        for column in Column.allCases {
            if let index = header.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == column.rawValue.lowercased()
            }) {
                positions[column] = index
            }
        }
        return positions
    }

    /// Whether a file with columns at `positions` is a Grosh export, which names each row's Card and links rather than
    /// leaving the import to work them out.
    static func isGroshExport(_ positions: [Column: Int]) -> Bool {
        positions[.card] != nil && positions[.linked] != nil
    }

    // MARK: Dates

    /// `day` as MoneyLover writes a date: `10/05/2026`, month first.
    static func date(_ day: CalendarDay) -> String {
        String(format: "%02d/%02d/%04d", day.month, day.day, day.year)
    }

    /// The day a date such as `01/31/2026` (month first, as MoneyLover writes it) names, or `nil` for anything else.
    static func day(from text: String) -> CalendarDay? {
        guard let match = text.wholeMatch(of: #/([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})/#),
            let month = Int(match.1), let day = Int(match.2), let year = Int(match.3),
            (1...12).contains(month),
            (1...CalendarMonth(year: year, month: month).dayCount).contains(day)
        else { return nil }
        return CalendarDay(year: year, month: month, day: day)
    }

    // MARK: Fields and records

    /// One line of the file, with MoneyLover's line ending: `fields` quoted as each needs (``field(_:)``).
    static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\r\n"
    }

    /// `text` as one CSV field: in double quotes, with its quotes doubled, when it holds a comma, a quote or a line
    /// break; as it is otherwise.
    static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// One record of a CSV file: its fields, and the line of the file it starts on.
    struct Record {
        /// The header is line 1.
        let line: Int
        let fields: [String]
    }

    /// Splits CSV text into records, reading back what ``line(_:)`` writes. A field in double quotes may hold commas,
    /// line breaks and doubled quotes (`""` for one `"`). Blank lines are skipped, and so is a byte order mark.
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
