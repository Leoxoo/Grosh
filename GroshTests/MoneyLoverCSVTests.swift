import Foundation
import Testing
@testable import Grosh

/// Reading a MoneyLover CSV export. Every fixture here is made up.
@Suite(.namedInTheLog)
struct MoneyLoverCSVTests {
    private func onlyRow(of csv: String) throws -> MoneyLoverRow {
        let rows = try MoneyLoverCSV.read(csv, currencyCode: "USD").rows
        try #require(rows.count == 1)
        return rows[0]
    }

    @Test func datesAreMonthFirst() throws {
        let row = try onlyRow(of: moneyLoverExport("1,01/31/2026,Café,-3.00,USD,Cash,,,,,"))

        #expect(row.day == CalendarDay(year: 2026, month: 1, day: 31))
    }

    @Test(arguments: [
        ("-74.910004", -74_91),
        ("-10.905", -10_91),
        ("12.344999", 12_34),
        ("1000", 1_000_00),
        ("-0.5", -50),
    ])
    func amountsAreRoundedToCents(text: String, cents: Int) throws {
        let row = try onlyRow(of: moneyLoverExport("1,10/05/2026,Café,\(text),USD,Cash,,,,,"))

        #expect(row.amount == Money(cents: cents))
    }

    @Test func withEventAndExcludeFromReportAreRead() throws {
        let rows = try MoneyLoverCSV.read(moneyLoverExport(
            "1,10/05/2026,Loan,-50,USD,Cash,Lunch money,Sam,Road trip,✅,",
            "2,10/04/2026,Café,-3.00,USD,Cash,,,,,"
        ), currencyCode: "USD").rows

        #expect(rows.map(\.withName) == ["Sam", ""])
        #expect(rows.map(\.eventName) == ["Road trip", ""])
        #expect(rows.map(\.isExcludedFromReport) == [true, false])
    }

    @Test func aQuotedNoteCanHoldCommasQuotesAndLineBreaks() throws {
        let rows = try MoneyLoverCSV.read(moneyLoverExport(
            "1,10/05/2026,Café,-3.00,USD,Cash,\"Lunch, then \"\"dessert\"\"\nwith friends\",,,,",
            "2,10/04/2026,Products,-8.20,USD,Cash,Groceries,,,,"
        ), currencyCode: "USD").rows

        #expect(rows.map(\.note) == ["Lunch, then \"dessert\"\nwith friends", "Groceries"])
        #expect(rows.map(\.amount) == [Money(cents: -3_00), Money(cents: -8_20)])
    }

    @Test func fieldsOtherThanTheNoteLoseTheSpacesAndLineBreaksAroundThem() throws {
        let row = try onlyRow(of: moneyLoverExport(
            "1, 10/05/2026 ,\"Café\n\", -3.00 ,USD,\" Cash\n\",\" Lunch\n\",\" Sam\n\",\"Trip\n\",\" \n\","
        ))

        #expect(row.day == CalendarDay(year: 2026, month: 10, day: 5))
        #expect(row.categoryName == "Café")
        #expect(row.amount == Money(cents: -3_00))
        #expect(row.walletName == "Cash")
        #expect(row.withName == "Sam")
        #expect(row.eventName == "Trip")
        #expect(!row.isExcludedFromReport)
        #expect(row.note == " Lunch\n")
    }

    @Test func aGroshExportsCardAndLinkedColumnsAreRead() throws {
        let file = try MoneyLoverCSV.read(([moneyLoverHeader + ",Card,Linked"] + [
            "1,10/05/2026,Café,-3.00,USD,Cash,,,,,, Chase ,1",
            "2,10/04/2026,Café,-3.00,USD,Cash,,,,,,,",
        ]).joined(separator: "\r\n"), currencyCode: "USD")

        #expect(file.rows.map(\.cardName) == ["Chase", ""])
        #expect(file.rows.map(\.link) == ["1", ""])
        #expect(file.isGroshExport)
    }

    @Test func aMoneyLoverExportHasNoCardOrLinkedColumn() throws {
        let file = try MoneyLoverCSV.read(moneyLoverExport("1,10/05/2026,Café,-3.00,USD,Cash,,,,,"), currencyCode: "USD")

        #expect(file.rows.map(\.cardName) == [nil])
        #expect(file.rows.map(\.link) == [nil])
        #expect(!file.isGroshExport)
    }

    // MARK: Files that can't be imported

    @Test func aFileWithoutMoneyLoversColumnsIsRefused() {
        #expect(throws: MoneyLoverImportError.notAMoneyLoverExport) {
            try MoneyLoverCSV.read("Date,Description,Amount\r\n10/05/2026,Coffee,-3.00\r\n", currencyCode: "USD")
        }
    }

    @Test func aFileWithNoTransactionsIsRefused() {
        #expect(throws: MoneyLoverImportError.noTransactions) {
            try MoneyLoverCSV.read(moneyLoverExport(), currencyCode: "USD")
        }
    }

    @Test(arguments: [
        "3,13/45/2026,Café,-3.00,USD,Cash,,,,,",
        "3,10/03/2026,Café,three,USD,Cash,,,,,",
        "3,10/03/2026,,-3.00,USD,Cash,,,,,",
        "3,10/03/2026,Café,-3.00,USD,,,,,,",
        "3,10/03/2026",
    ])
    func anUnreadableRowIsRefusedWithItsLineInTheFile(row: String) {
        // The note on line 2 runs over two lines, so the third row starts on line 5.
        #expect(throws: MoneyLoverImportError.unreadableRow(line: 5)) {
            try MoneyLoverCSV.read(moneyLoverExport(
                "1,10/05/2026,Café,-3.00,USD,Cash,\"Two\nlines\",,,,",
                "2,10/04/2026,Café,-3.00,USD,Cash,,,,,",
                row
            ), currencyCode: "USD")
        }
    }

    @Test func missingTrailingColumnsAreEmpty() throws {
        let row = try onlyRow(of: moneyLoverExport("1,10/05/2026,Café,-3.00,USD,Cash"))

        #expect(row.note == "")
        #expect(!row.isExcludedFromReport)
    }
}
