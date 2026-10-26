import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Debts & Loans: Show by people (ADR-0009, ADR-0010). One entry per Person with what they owe the user (Loans plus Owes
/// me, combined) and what the user owes them (Debts), one amount per currency, never netted; open amounts flagged and left
/// out of the figures; people with something outstanding first, then Settled; hidden people listed while anything is
/// outstanding.
@MainActor
@Suite(.namedInTheLog)
struct DebtsAndLoansByPersonTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private let lentOn = day(2026, 5, 27)

    init() throws {
        fixture = try ExpectationFixture()
    }

    /// A Loan (`.loan`) or Debt (`.debt`) of `cents` with `person`, saved as the Add sheet saves it, in Checking unless
    /// another wallet is given.
    @discardableResult
    private func record(
        _ role: LockedRole, _ cents: Int, with person: Person, in wallet: Wallet? = nil
    ) throws -> Transaction {
        var draft = TransactionDraft(type: .debtLoan, day: lentOn)
        draft.wallet = wallet ?? fixture.checking
        draft.amount = Money(cents: cents)
        draft.category = try context.lockedCategory(role)
        draft.people = [person]
        return try Transaction.create(draft, in: context)
    }

    private func settle(_ original: Transaction) throws {
        let outstanding = try #require(try LoanOrDebt(original, in: context)).outstanding
        var draft = try DebtPaymentDraft(settling: original, on: day(2026, 6, 15), in: context)
        draft.amount = outstanding
        try DebtPayment.record(draft, in: context)
    }

    private func listing() throws -> DebtsAndLoansByPerson {
        try DebtsAndLoansByPerson(in: context)
    }

    private func euroWallet() -> Wallet {
        let wallet = Wallet(name: "Euro")
        wallet.currencyCode = "EUR"
        context.insert(wallet)
        return wallet
    }

    // MARK: Grouping

    @Test func eachPersonHasTheirLoansDebtsAndExpectations() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let loan = try record(.loan, 100_00, with: alex)
        let debt = try record(.debt, 40_00, with: alex)
        let samsLoan = try record(.loan, 15_00, with: sam)
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])

        let everyone = try listing()

        let alexEntry = try #require(everyone.entry(for: alex))
        #expect(alexEntry.loans.map(\.original) == [loan])
        #expect(alexEntry.debts.map(\.original) == [debt])
        #expect(alexEntry.expectations == [try fixture.expectation(of: alex, on: dinner)])
        let samEntry = try #require(everyone.entry(for: sam))
        #expect(samEntry.loans.map(\.original) == [samsLoan])
        #expect(samEntry.debts.isEmpty)
        #expect(samEntry.expectations.isEmpty)
    }

    @Test func aPersonWithNothingRecordedIsNotListed() throws {
        let alex = try fixture.person("Alex")
        let nobody = try fixture.person("Nobody")
        try record(.loan, 10_00, with: alex)

        let everyone = try listing()

        #expect(everyone.entry(for: nobody) == nil)
        #expect((everyone.open + everyone.settled).map(\.person) == [alex])
    }

    @Test func anExpenseInRecentlyDeletedLeavesItsExpectationsOut() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])

        try dinner.delete(.onlySelected, in: context, at: .now)

        #expect(try listing().entry(for: alex) == nil)
    }

    // MARK: Separate figures, per currency

    @Test func loansAndOwesMeAreCombinedIntoWhatTheyOweYou() throws {
        let alex = try fixture.person("Alex")
        try record(.loan, 100_00, with: alex)
        try fixture.dinner(owing: [(alex, 30_00)])

        let entry = try #require(try listing().entry(for: alex))

        #expect(entry.owesYou == [Money(cents: 130_00)])
        #expect(entry.youOwe.isEmpty)
    }

    @Test func debtsAreWhatYouOweAndAreNeverNettedAgainstWhatTheyOweYou() throws {
        let alex = try fixture.person("Alex")
        try record(.loan, 100_00, with: alex)
        try record(.debt, 40_00, with: alex)

        let entry = try #require(try listing().entry(for: alex))

        #expect(entry.owesYou == [Money(cents: 100_00)])
        #expect(entry.youOwe == [Money(cents: 40_00)])
    }

    @Test func eachCurrencyHasItsOwnAmountAndNeverAddsToAnother() throws {
        let alex = try fixture.person("Alex")
        let euros = euroWallet()
        try record(.loan, 100_00, with: alex)
        try record(.loan, 20_00, with: alex, in: euros)
        try record(.loan, 5_00, with: alex, in: euros)
        try record(.debt, 8_00, with: alex, in: euros)
        try fixture.dinner(owing: [(alex, 30_00)])

        let entry = try #require(try listing().entry(for: alex))

        #expect(entry.owesYou == [Money(cents: 25_00, currencyCode: "EUR"), Money(cents: 130_00)])
        #expect(entry.youOwe == [Money(cents: 8_00, currencyCode: "EUR")])
    }

    @Test func figuresCountWhatIsStillOutstandingAfterPayments() throws {
        let alex = try fixture.person("Alex")
        let loan = try record(.loan, 100_00, with: alex)
        var payment = try DebtPaymentDraft(settling: loan, on: day(2026, 6, 15), in: context)
        payment.amount = Money(cents: 60_00)
        try DebtPayment.record(payment, in: context)
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        try fixture.pay(10_00, on: try fixture.expectation(of: alex, on: dinner))

        let entry = try #require(try listing().entry(for: alex))

        #expect(entry.owesYou == [Money(cents: 60_00)])
    }

    // MARK: Open amounts

    @Test func anOpenAmountIsFlaggedAndAddedToNoFigure() throws {
        let alex = try fixture.person("Alex")
        try record(.loan, 100_00, with: alex)
        try fixture.dinner(owing: [(alex, nil)])
        try fixture.dinner(owing: [(alex, nil)])

        let entry = try #require(try listing().entry(for: alex))

        #expect(entry.owesYou == [Money(cents: 100_00)])
        #expect(entry.openAmountCount == 2)
        #expect(entry.hasOpenAmounts)
    }

    @Test func aPersonWithOnlyAnOpenAmountStillHasSomethingOutstanding() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, nil)])

        let everyone = try listing()

        let entry = try #require(everyone.entry(for: alex))
        #expect(entry.owesYou.isEmpty)
        #expect(entry.openAmountCount == 1)
        #expect(!entry.isSettled)
        #expect(everyone.open.map(\.person) == [alex])

        try fixture.expectation(of: alex, on: dinner).close()

        let closed = try #require(try listing().entry(for: alex))
        #expect(closed.openAmountCount == 0)
        #expect(closed.isSettled)
    }

    // MARK: Ordering and Settled

    @Test func peopleWithSomethingOutstandingComeFirstThenSettledEachByName() throws {
        let zoe = try fixture.person("Zoe")
        let alex = try fixture.person("Alex")
        let ben = try fixture.person("Ben")
        let cleo = try fixture.person("Cleo")
        let dana = try fixture.person("Dana")
        try record(.loan, 10_00, with: zoe)
        try settle(try record(.loan, 20_00, with: alex))
        try record(.debt, 30_00, with: ben)
        try settle(try record(.debt, 40_00, with: cleo))
        try fixture.dinner(owing: [(dana, nil)])

        let everyone = try listing()

        #expect(everyone.open.map(\.person.name) == ["Ben", "Dana", "Zoe"])
        #expect(everyone.settled.map(\.person.name) == ["Alex", "Cleo"])
        #expect(everyone.settled.allSatisfy { $0.isSettled })
        #expect(everyone.open.allSatisfy { !$0.isSettled })
    }

    @Test func aPersonIsSettledOnlyWhenEveryLoanDebtAndExpectationIs() throws {
        let alex = try fixture.person("Alex")
        let loan = try record(.loan, 100_00, with: alex)
        let debt = try record(.debt, 40_00, with: alex)
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        try settle(loan)
        try settle(debt)
        #expect(try listing().open.map(\.person) == [alex])

        try owed.forgive()

        let everyone = try listing()
        #expect(everyone.open.isEmpty)
        #expect(everyone.settled.map(\.person) == [alex])
        let entry = try #require(everyone.entry(for: alex))
        #expect(entry.owesYou.isEmpty)
        #expect(entry.youOwe.isEmpty)
    }

    // MARK: Hidden people

    @Test func aHiddenPersonIsListedWhileAnythingIsOutstanding() throws {
        let alex = try fixture.person("Alex")
        let loan = try record(.loan, 100_00, with: alex)
        try alex.hide()

        #expect(try listing().open.map(\.person) == [alex])

        try settle(loan)

        let everyone = try listing()
        #expect(everyone.open.isEmpty)
        #expect(everyone.settled.isEmpty)
    }

    @Test func aHiddenPersonWithOnlyAnOpenAmountIsListed() throws {
        let alex = try fixture.person("Alex")
        try fixture.dinner(owing: [(alex, nil)])
        try alex.hide()

        #expect(try listing().open.map(\.person) == [alex])
    }

    // MARK: Text button

    /// The message is copied or shared when there is no number to text, so a phone isn't needed for the button.
    @Test func theTextButtonIsOnEveryoneWhoOwesOrIsOwedWithOrWithoutAPhone() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let kim = try fixture.person("Kim")
        alex.phone = "555 0100"
        kim.phone = "555 0199"
        try record(.loan, 10_00, with: alex)
        try record(.loan, 10_00, with: sam)
        try settle(try record(.loan, 10_00, with: kim))

        let everyone = try listing()

        let withPhone = try #require(everyone.entry(for: alex))
        let withoutPhone = try #require(everyone.entry(for: sam))
        let settled = try #require(everyone.entry(for: kim))
        #expect(withPhone.canText)
        #expect(withoutPhone.canText)
        #expect(!settled.canText)
    }

    // MARK: The remembered choice

    @Test func showByLoanOrDebtIsTodaysListAndTheChoiceIsKeptByItsRawValue() {
        #expect(DebtsLoansGrouping.default == .loanOrDebt)
        #expect(DebtsLoansGrouping(rawValue: DebtsLoansGrouping.people.rawValue) == .people)
        #expect(DebtsLoansGrouping(rawValue: DebtsLoansGrouping.loanOrDebt.rawValue) == .loanOrDebt)
        #expect(DebtsLoansGrouping(rawValue: "something else") == nil)
    }
}
