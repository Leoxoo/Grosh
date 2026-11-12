import Foundation
import SwiftData
import Testing
@testable import Grosh

@MainActor
@Suite(.namedInTheLog)
struct CardManagementTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(name: "Checking", startingBalance: Money(cents: 0), on: today, in: container.mainContext)
    }

    @Test func aCreditCardCanHaveAStatementDate() throws {
        let card = try Card.create(
            CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking, statementDay: 31),
            in: context
        )

        #expect(card.name == "Apple Card")
        #expect(card.kind == .credit)
        #expect(card.payingWallet == checking)
        #expect(card.statementDay == 31)
    }

    @Test func aStatementDateFallsOnTheMonthsLastDayWhenTheMonthIsShorter() throws {
        let appleCard = try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking, statementDay: 31), in: context)
        let chase = try Card.create(CardDraft(name: "Chase", kind: .credit, payingWallet: checking, statementDay: 15), in: context)
        let debit = try Card.create(CardDraft(name: "Navy Federal Debit", kind: .debit, payingWallet: checking), in: context)

        #expect(statementCloses(appleCard, year: 2026, month: 10) == CalendarDay(year: 2026, month: 10, day: 31))
        #expect(statementCloses(appleCard, year: 2026, month: 4) == CalendarDay(year: 2026, month: 4, day: 30))
        #expect(statementCloses(appleCard, year: 2026, month: 2) == CalendarDay(year: 2026, month: 2, day: 28))
        #expect(statementCloses(appleCard, year: 2028, month: 2) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(statementCloses(chase, year: 2026, month: 2) == CalendarDay(year: 2026, month: 2, day: 15))
        // With no statement date, a Card's period is the calendar month.
        #expect(statementCloses(debit, year: 2026, month: 2) == CalendarDay(year: 2026, month: 2, day: 28))
    }

    /// The last day of `card`'s statement period that starts in `month` of `year`, as its Card statement shows it.
    private func statementCloses(_ card: Card, year: Int, month: Int) -> CalendarDay {
        CardPeriod(containing: CalendarDay(year: year, month: month, day: 1), statementDay: card.statementDay).lastDay
    }

    private func allCards() throws -> [Card] {
        try context.fetch(FetchDescriptor<Card>())
    }

    @Test func theCardsListAndFilterKeepACardWithNoPayingWallet() throws {
        let archived = try Card.create(CardDraft(name: "Old", kind: .debit, payingWallet: checking), in: context)
        try archived.archive()
        let unpaid = Card(name: "Unpaid", kind: .debit, payingWallet: nil)
        context.insert(unpaid)
        try context.save()

        #expect(try context.fetch(Card.unarchived) == [unpaid])
        #expect(try context.fetch(Card.archived) == [archived])
        #expect(try Set(context.fetch(Card.listed)) == [archived, unpaid])
    }

    @Test func theStatementDateCanOnlyBeSetOnCreditCards() throws {
        #expect(throws: CardRuleError.statementDateRequiresCredit) {
            try Card.create(
                CardDraft(name: "Navy Federal Debit", kind: .debit, payingWallet: checking, statementDay: 15),
                in: context
            )
        }
        #expect(try allCards().isEmpty)
    }

    @Test(arguments: [0, 32, -1])
    func theStatementDateIsADayOfTheMonth(day: Int) throws {
        #expect(throws: CardRuleError.statementDayOutOfRange) {
            try Card.create(CardDraft(name: "Chase", kind: .credit, payingWallet: checking, statementDay: day), in: context)
        }
    }

    @Test func editingACardRefusesAStatementDateOnDebitAndLeavesTheCardAsItWas() throws {
        let card = try Card.create(
            CardDraft(name: "Navy Federal", kind: .credit, payingWallet: checking, statementDay: 12),
            in: context
        )
        var details = CardDraft(card)
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
            try Card.create(CardDraft(name: "Amex", kind: .credit, payingWallet: checking, lastFourDigits: digits), in: context)
        }
    }

    @Test func theLastFourDigitsAreOptional() throws {
        let blank = try Card.create(CardDraft(name: "Citi", kind: .credit, payingWallet: checking, lastFourDigits: " "), in: context)
        let none = try Card.create(CardDraft(name: "Petal", kind: .credit, payingWallet: checking), in: context)

        #expect(blank.lastFourDigits == nil)
        #expect(none.lastFourDigits == nil)
    }

    @Test func aCardNeedsANameAndAPayingWallet() throws {
        #expect(throws: CardRuleError.missingName) {
            try Card.create(CardDraft(name: "  ", kind: .debit, payingWallet: checking), in: context)
        }
        #expect(throws: CardRuleError.missingPayingWallet) {
            try Card.create(CardDraft(name: "Discover", kind: .credit, payingWallet: nil), in: context)
        }

        let card = try Card.create(CardDraft(name: " Discover ", kind: .credit, payingWallet: checking), in: context)
        #expect(card.name == "Discover")
    }

    @Test func thePickerOffersOnlyCardsPaidFromTheTransactionsWalletInTheOrderTheyWereAdded() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        try context.addCard("Wells Fargo", paidFrom: checking)
        try context.addCard("Savings Debit", kind: .debit, paidFrom: savings)
        try context.addCard("Navy Federal Debit", kind: .debit, paidFrom: checking)
        try context.addCard("Apple Card", paidFrom: checking)

        #expect(Card.pickerChoices(for: checking, keeping: nil).map(\.name) == ["Wells Fargo", "Navy Federal Debit", "Apple Card"])
        #expect(Card.pickerChoices(for: savings, keeping: nil).map(\.name) == ["Savings Debit"])
        #expect(Card.pickerChoices(for: nil, keeping: nil).isEmpty)
    }

    private func addExpense(_ cents: Int, paidWith card: Card?, on day: CalendarDay? = nil) throws -> Transaction {
        let transaction = Transaction.insert(
            cents: -cents, on: day ?? today, wallet: nil, category: nil, in: context
        )
        transaction.wallet = checking
        transaction.category = try context.lockedCategory(.otherExpense)
        transaction.card = card
        return transaction
    }

    @Test func anArchivedCardLeavesThePickerButStaysVisibleOnPastTransactions() throws {
        let navyFederal = try context.addCard("Navy Federal", paidFrom: checking)
        let appleCard = try context.addCard("Apple Card", paidFrom: checking)
        let lunch = try addExpense(12_76, paidWith: navyFederal)

        try navyFederal.archive()

        #expect(Card.pickerChoices(for: checking, keeping: nil).map(\.name) == ["Apple Card"])
        #expect(lunch.card == navyFederal)
        #expect(navyFederal.transactions == [lunch])
        // Editing the old transaction still shows the Card it was paid with.
        #expect(Card.pickerChoices(for: checking, keeping: navyFederal).map(\.name) == ["Apple Card", "Navy Federal"])
        #expect(Card.pickerChoices(for: checking, keeping: appleCard).map(\.name) == ["Apple Card"])
    }

    @Test func anUnarchivedCardReturnsToThePickerInItsPlace() throws {
        let navyFederal = try context.addCard("Navy Federal", paidFrom: checking)
        try context.addCard("Apple Card", paidFrom: checking)
        try navyFederal.archive()

        try navyFederal.unarchive()

        #expect(Card.pickerChoices(for: checking, keeping: nil).map(\.name) == ["Navy Federal", "Apple Card"])
    }

    @Test func mergingMovesEveryTransactionToTheTargetCardAndRemovesTheSource() throws {
        let nfcu = try context.addCard("NFCU", paidFrom: checking)
        let navyFederal = try context.addCard("Navy Federal", paidFrom: checking)
        let lunch = try addExpense(12_76, paidWith: nfcu)
        let groceries = try addExpense(84_10, paidWith: nfcu, on: CalendarDay(year: 2026, month: 9, day: 30))
        let petrol = try addExpense(40_00, paidWith: navyFederal)

        try nfcu.merge(into: navyFederal)

        #expect(lunch.card == navyFederal)
        #expect(groceries.card == navyFederal)
        #expect(petrol.card == navyFederal)
        #expect(Set(navyFederal.transactions ?? []) == [lunch, groceries, petrol])
        #expect(try allCards().map(\.name) == ["Navy Federal"])
        #expect(walletBalance(checking, asOf: today) == Money(cents: -136_86))
    }

    @Test func mergingKeepsTheImageOfTheCardMergedInto() throws {
        let nfcu = try context.addCard("NFCU", paidFrom: checking)
        let navyFederal = try context.addCard("Navy Federal", paidFrom: checking)
        nfcu.imageData = Data([4, 5, 6])
        navyFederal.imageData = Data([1, 2, 3])

        try nfcu.merge(into: navyFederal)

        #expect(navyFederal.imageData == Data([1, 2, 3]))
    }

    @Test func aCardMergesOnlyIntoTheOtherUnarchivedCardsPaidFromTheSameWallet() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let nfcu = try context.addCard("NFCU", paidFrom: checking)
        try context.addCard("Savings Debit", kind: .debit, paidFrom: savings)
        try context.addCard("Navy Federal", paidFrom: checking)
        try context.addCard("Old Amex", paidFrom: checking).archive()
        try context.addCard("Apple Card", paidFrom: checking)

        #expect(nfcu.mergeTargets.map(\.name) == ["Navy Federal", "Apple Card"])
    }

    @Test func mergingIntoACardPaidFromAnotherWalletIsRefusedAndMovesNothing() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let nfcu = try context.addCard("NFCU", paidFrom: checking)
        let savingsDebit = try context.addCard("Savings Debit", kind: .debit, paidFrom: savings)
        let lunch = try addExpense(12_76, paidWith: nfcu)

        #expect(throws: CardRuleError.mergeIntoAnotherWallet) { try nfcu.merge(into: savingsDebit) }
        #expect(lunch.card == nfcu)
        #expect(Set(try allCards()) == [nfcu, savingsDebit])
    }

    @Test func mergingIntoAnArchivedCardIsRefused() throws {
        let nfcu = try context.addCard("NFCU", paidFrom: checking)
        let oldAmex = try context.addCard("Old Amex", paidFrom: checking)
        try oldAmex.archive()
        let lunch = try addExpense(12_76, paidWith: nfcu)

        #expect(throws: CardRuleError.mergeIntoArchived) { try nfcu.merge(into: oldAmex) }
        #expect(lunch.card == nfcu)
    }

    @Test func aCardThatPaidForTransactionsKeepsItsPayingWallet() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let nfcu = try context.addCard("NFCU", paidFrom: checking)
        _ = try addExpense(12_76, paidWith: nfcu)
        var details = CardDraft(nfcu)
        details.payingWallet = savings
        details.name = "Navy Federal"

        #expect(throws: CardRuleError.payingWalletHasTransactions) { try nfcu.update(with: details) }
        #expect(nfcu.payingWallet == checking)
        #expect(nfcu.name == "NFCU")
    }

    @Test func aCardWithoutTransactionsCanMoveToAnotherPayingWallet() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        let unused = try context.addCard("PayPal", paidFrom: checking)
        var details = CardDraft(unused)
        details.payingWallet = savings

        try unused.update(with: details)

        #expect(unused.payingWallet == savings)
    }

    @Test func aCardCannotBeMergedIntoItself() throws {
        let amex = try context.addCard("Amex", paidFrom: checking)
        let dinner = try addExpense(55_00, paidWith: amex)

        #expect(throws: CardRuleError.mergeIntoItself) { try amex.merge(into: amex) }
        #expect(try allCards() == [amex])
        #expect(dinner.card == amex)
    }

    @Test func deletingACardThatHasTransactionsRequiresMergingFirst() throws {
        let boa = try context.addCard("Bank of America", paidFrom: checking)
        let citi = try context.addCard("Citi", paidFrom: checking)
        let unused = try context.addCard("PayPal", paidFrom: checking)
        let dinner = try addExpense(55_00, paidWith: boa)

        #expect(throws: CardRuleError.hasTransactions) { try boa.delete() }
        #expect(dinner.card == boa)

        try unused.delete()
        try boa.merge(into: citi)

        #expect(try allCards() == [citi])
        #expect(dinner.card == citi)
    }
}
