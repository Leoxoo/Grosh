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

    // MARK: MoneyLover's tab-separated UTF-16 export

    /// How MoneyLover's newer export writes a file: tab-separated, its notes before its wallets, no With, Event or
    /// Exclude from report column, quoted notes that may hold commas and line breaks.
    private let tabSeparatedExport = [
        "Id\tDate\tCategory\tAmount\tCurrency\tNote\tWallet",
        "1\t07/13/2026\tTips\t143.00\tUSD\tLost tips\tCash",
        "2\t07/13/2026\tOutgoing transfer\t-928.00\tUSD\tSend to Checking\tCash",
        "3\t12/31/2023\tGifts\t160.00\tUSD\t\"Ann, Sam present\nfor December\"\tSaving (Bank)",
        "4\t06/25/2026\tCafé\t-5.00\tUSD\t\tCash",
    ].joined(separator: "\r\n") + "\r\n"

    @Test func aTabSeparatedExportIsRead() throws {
        let rows = try MoneyLoverCSV.read(tabSeparatedExport, currencyCode: "USD").rows

        #expect(rows.map(\.line) == [2, 3, 4, 6])
        #expect(rows.map(\.day) == [
            CalendarDay(year: 2026, month: 7, day: 13), CalendarDay(year: 2026, month: 7, day: 13),
            CalendarDay(year: 2023, month: 12, day: 31), CalendarDay(year: 2026, month: 6, day: 25),
        ])
        #expect(rows.map(\.categoryName) == ["Tips", "Outgoing transfer", "Gifts", "Café"])
        #expect(rows.map(\.amount) == [
            Money(cents: 143_00), Money(cents: -928_00), Money(cents: 160_00), Money(cents: -5_00),
        ])
        #expect(rows.map(\.note) == ["Lost tips", "Send to Checking", "Ann, Sam present\nfor December", ""])
        #expect(rows.map(\.walletName) == ["Cash", "Cash", "Saving (Bank)", "Cash"])
        #expect(rows.allSatisfy { $0.withName.isEmpty && $0.eventName.isEmpty && !$0.isExcludedFromReport })
    }

    @Test(arguments: [String.Encoding.utf16LittleEndian, .utf16BigEndian])
    func aUTF16FileWithAByteOrderMarkIsRead(encoding: String.Encoding) throws {
        let bom: [UInt8] = encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]
        let data = Data(bom) + (try #require(tabSeparatedExport.data(using: encoding)))

        let fromData = try MoneyLoverCSV.read(data, currencyCode: "USD")

        #expect(fromData == (try MoneyLoverCSV.read(tabSeparatedExport, currencyCode: "USD")))
    }

    @Test func aUTF8FileIsRead() throws {
        let text = moneyLoverExport("1,10/05/2026,Café,-3.00,USD,Cash,,,,,")
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)

        #expect(try MoneyLoverCSV.read(data, currencyCode: "USD") == (try MoneyLoverCSV.read(text, currencyCode: "USD")))
    }

    // MARK: Files that can't be imported

    @Test func aFileThatIsntTextIsRefused() {
        #expect(throws: MoneyLoverImportError.notAMoneyLoverExport) {
            try MoneyLoverCSV.read(Data([0xC3, 0x28, 0xFF]), currencyCode: "USD")
        }
    }

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
