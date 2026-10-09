import SwiftData
import Testing
@testable import Grosh

@MainActor
struct CardManagementTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(name: "Checking", startingBalance: Money(cents: 0), on: today, in: container.mainContext)
    }

    @Test func aCreditCardCanHaveAStatementDate() throws {
        let card = try Card.create(
            CardDetails(name: "Apple Card", kind: .credit, payingWallet: checking, statementDay: 31),
            in: context
        )

        #expect(card.name == "Apple Card")
        #expect(card.kind == .credit)
        #expect(card.payingWallet == checking)
        #expect(card.statementDay == 31)
    }

    @Test func aStatementDateFallsOnTheMonthsLastDayWhenTheMonthIsShorter() throws {
        let appleCard = try Card.create(CardDetails(name: "Apple Card", kind: .credit, payingWallet: checking, statementDay: 31), in: context)
        let chase = try Card.create(CardDetails(name: "Chase", kind: .credit, payingWallet: checking, statementDay: 15), in: context)
        let debit = try Card.create(CardDetails(name: "Navy Federal Debit", kind: .debit, payingWallet: checking), in: context)

        #expect(appleCard.statementClosingDay(year: 2026, month: 10) == CalendarDay(year: 2026, month: 10, day: 31))
        #expect(appleCard.statementClosingDay(year: 2026, month: 4) == CalendarDay(year: 2026, month: 4, day: 30))
        #expect(appleCard.statementClosingDay(year: 2026, month: 2) == CalendarDay(year: 2026, month: 2, day: 28))
        #expect(appleCard.statementClosingDay(year: 2028, month: 2) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(chase.statementClosingDay(year: 2026, month: 2) == CalendarDay(year: 2026, month: 2, day: 15))
        #expect(debit.statementClosingDay(year: 2026, month: 2) == nil)
    }

    private func allCards() throws -> [Card] {
        try context.fetch(FetchDescriptor<Card>())
    }

    @Test func theStatementDateCanOnlyBeSetOnCreditCards() throws {
        #expect(throws: CardRuleError.statementDateRequiresCredit) {
            try Card.create(
                CardDetails(name: "Navy Federal Debit", kind: .debit, payingWallet: checking, statementDay: 15),
                in: context
            )
        }
        #expect(try allCards().isEmpty)
    }

    @Test(arguments: [0, 32, -1])
    func theStatementDateIsADayOfTheMonth(day: Int) throws {
        #expect(throws: CardRuleError.statementDayOutOfRange) {
            try Card.create(CardDetails(name: "Chase", kind: .credit, payingWallet: checking, statementDay: day), in: context)
        }
    }

    @Test func editingACardRefusesAStatementDateOnDebitAndLeavesTheCardAsItWas() throws {
        let card = try Card.create(
            CardDetails(name: "Navy Federal", kind: .credit, payingWallet: checking, statementDay: 12),
            in: context
        )
        var details = CardDetails(card)
        details.kind = .debit

        #expect(throws: CardRuleError.statementDateRequiresCredit) { try card.update(with: details) }
        #expect(card.kind == .credit)
        #expect(card.statementDay == 12)

        details.statementDay = nil
        details.name = "Navy Federal Debit"
        details.lastFourDigits = "4821"
        try card.update(with: details)
        #expect(card.name == "Navy Federal Debit")
        #expect(card.kind == .debit)
        #expect(card.statementDay == nil)
        #expect(card.lastFourDigits == "4821")
    }

    @Test(arguments: ["123", "12345", "12a4", "١٢٣٤"])
    func theLastDigitsAreExactlyFourDigits(digits: String) throws {
        #expect(throws: CardRuleError.invalidLastFourDigits) {
            try Card.create(CardDetails(name: "Amex", kind: .credit, payingWallet: checking, lastFourDigits: digits), in: context)
        }
    }

    @Test func theLastFourDigitsAreOptional() throws {
        let blank = try Card.create(CardDetails(name: "Citi", kind: .credit, payingWallet: checking, lastFourDigits: " "), in: context)
        let none = try Card.create(CardDetails(name: "Petal", kind: .credit, payingWallet: checking), in: context)

        #expect(blank.lastFourDigits == nil)
        #expect(none.lastFourDigits == nil)
    }

    @Test func aCardNeedsANameAndAPayingWallet() throws {
        #expect(throws: CardRuleError.missingName) {
            try Card.create(CardDetails(name: "  ", kind: .debit, payingWallet: checking), in: context)
        }
        #expect(throws: CardRuleError.missingPayingWallet) {
            try Card.create(CardDetails(name: "Discover", kind: .credit, payingWallet: nil), in: context)
        }

        let card = try Card.create(CardDetails(name: " Discover ", kind: .credit, payingWallet: checking), in: context)
        #expect(card.name == "Discover")
    }

    @discardableResult
    private func addCard(_ name: String, kind: CardKind = .credit, paidFrom wallet: Wallet? = nil) throws -> Card {
        try Card.create(CardDetails(name: name, kind: kind, payingWallet: wallet ?? checking), in: context)
    }

    @Test func thePickerOffersOnlyCardsPaidFromTheTransactionsWalletInTheOrderTheyWereAdded() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        try addCard("Wells Fargo")
        try addCard("Savings Debit", kind: .debit, paidFrom: savings)
        try addCard("Navy Federal Debit", kind: .debit)
        try addCard("Apple Card")

        #expect(Card.pickerChoices(for: checking, keeping: nil).map(\.name) == ["Wells Fargo", "Navy Federal Debit", "Apple Card"])
        #expect(Card.pickerChoices(for: savings, keeping: nil).map(\.name) == ["Savings Debit"])
        #expect(Card.pickerChoices(for: nil, keeping: nil).isEmpty)
    }

    private func addExpense(_ cents: Int, paidWith card: Card?, on day: CalendarDay? = nil) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: -cents), day: day ?? today, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = checking
        transaction.category = try context.lockedCategory(.otherExpense)
        transaction.card = card
        return transaction
    }

    @Test func anArchivedCardLeavesThePickerButStaysVisibleOnPastTransactions() throws {
        let navyFederal = try addCard("Navy Federal")
        let appleCard = try addCard("Apple Card")
        let lunch = try addExpense(12_76, paidWith: navyFederal)

        navyFederal.archive()

        #expect(Card.pickerChoices(for: checking, keeping: nil).map(\.name) == ["Apple Card"])
        #expect(lunch.card == navyFederal)
        #expect(navyFederal.transactions == [lunch])
        // Editing the old transaction still shows the Card it was paid with.
        #expect(Card.pickerChoices(for: checking, keeping: navyFederal).map(\.name) == ["Apple Card", "Navy Federal"])
        #expect(Card.pickerChoices(for: checking, keeping: appleCard).map(\.name) == ["Apple Card"])
    }

    @Test func anUnarchivedCardReturnsToThePickerInItsPlace() throws {
        let navyFederal = try addCard("Navy Federal")
        try addCard("Apple Card")
        navyFederal.archive()

        navyFederal.unarchive()

        #expect(Card.pickerChoices(for: checking, keeping: nil).map(\.name) == ["Navy Federal", "Apple Card"])
    }

    @Test func mergingMovesEveryTransactionToTheTargetCardAndRemovesTheSource() throws {
        let nfcu = try addCard("NFCU")
        let navyFederal = try addCard("Navy Federal")
        let lunch = try addExpense(12_76, paidWith: nfcu)
        let groceries = try addExpense(84_10, paidWith: nfcu, on: CalendarDay(year: 2026, month: 9, day: 30))
        let petrol = try addExpense(40_00, paidWith: navyFederal)

        try nfcu.merge(into: navyFederal, in: context)

        #expect(lunch.card == navyFederal)
        #expect(groceries.card == navyFederal)
        #expect(petrol.card == navyFederal)
        #expect(Set(navyFederal.transactions ?? []) == [lunch, groceries, petrol])
        #expect(try allCards().map(\.name) == ["Navy Federal"])
        #expect(checking.balance(asOf: today) == Money(cents: -136_86))
    }

    @Test func aCardMergesOnlyIntoTheOtherUnarchivedCardsPaidFromTheSameWallet() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let nfcu = try addCard("NFCU")
        try addCard("Savings Debit", kind: .debit, paidFrom: savings)
        try addCard("Navy Federal")
        try addCard("Old Amex").archive()
        try addCard("Apple Card")

        #expect(nfcu.mergeTargets.map(\.name) == ["Navy Federal", "Apple Card"])
    }

    @Test func mergingIntoACardPaidFromAnotherWalletIsRefusedAndMovesNothing() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let nfcu = try addCard("NFCU")
        let savingsDebit = try addCard("Savings Debit", kind: .debit, paidFrom: savings)
        let lunch = try addExpense(12_76, paidWith: nfcu)

        #expect(throws: CardRuleError.mergeIntoAnotherWallet) { try nfcu.merge(into: savingsDebit, in: context) }
        #expect(lunch.card == nfcu)
        #expect(Set(try allCards()) == [nfcu, savingsDebit])
    }

    @Test func mergingIntoAnArchivedCardIsRefused() throws {
        let nfcu = try addCard("NFCU")
        let oldAmex = try addCard("Old Amex")
        oldAmex.archive()
        let lunch = try addExpense(12_76, paidWith: nfcu)

        #expect(throws: CardRuleError.mergeIntoArchived) { try nfcu.merge(into: oldAmex, in: context) }
        #expect(lunch.card == nfcu)
    }

    @Test func aCardThatPaidForTransactionsKeepsItsPayingWallet() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let nfcu = try addCard("NFCU")
        try addExpense(12_76, paidWith: nfcu)
        var details = CardDetails(nfcu)
        details.payingWallet = savings
        details.name = "Navy Federal"

        #expect(throws: CardRuleError.payingWalletHasTransactions) { try nfcu.update(with: details) }
        #expect(nfcu.payingWallet == checking)
        #expect(nfcu.name == "NFCU")
    }

    @Test func aCardWithoutTransactionsCanMoveToAnotherPayingWallet() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let unused = try addCard("PayPal")
        var details = CardDetails(unused)
        details.payingWallet = savings

        try unused.update(with: details)

        #expect(unused.payingWallet == savings)
    }

    @Test func aCardCannotBeMergedIntoItself() throws {
        let amex = try addCard("Amex")
        let dinner = try addExpense(55_00, paidWith: amex)

        #expect(throws: CardRuleError.mergeIntoItself) { try amex.merge(into: amex, in: context) }
        #expect(try allCards() == [amex])
        #expect(dinner.card == amex)
    }

    @Test func deletingACardThatHasTransactionsRequiresMergingFirst() throws {
        let boa = try addCard("Bank of America")
        let citi = try addCard("Citi")
        let unused = try addCard("PayPal")
        let dinner = try addExpense(55_00, paidWith: boa)

        #expect(throws: CardRuleError.hasTransactions) { try boa.delete(in: context) }
        #expect(dinner.card == boa)

        try unused.delete(in: context)
        try boa.merge(into: citi, in: context)

        #expect(try allCards() == [citi])
        #expect(dinner.card == citi)
    }
}
