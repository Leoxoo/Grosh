import Foundation
import SwiftData

/// How Account → Debts & Loans lists its content, remembered between visits: **Show by people** (one row per Person) or
/// **Show by Loan/Debt** (one row per Loan, Debt and Expected reimbursement, as it was before people).
nonisolated enum DebtsLoansGrouping: String, Hashable, Sendable {
    case people
    case loanOrDebt

    /// Where the choice is kept.
    static let storageKey = "debtsLoans.grouping"
    /// The list as it was before Show by people existed.
    static let `default` = DebtsLoansGrouping.loanOrDebt
}

/// One Person in Show by people: their Loans, Debts and Expected reimbursements, and what they come to (ADR-0009,
/// ADR-0010).
///
/// ``owesYou`` is what the Person owes the user: the Loans' outstanding amounts plus the open Expected reimbursements',
/// combined into one figure per currency. ``youOwe`` is what the user owes them: the Debts' outstanding amounts. The two
/// are never netted against each other, and a currency is never added to another. An Expected reimbursement with no
/// amount is left out of every figure and counted in ``openAmountCount``, which the row flags ("+1 open").
struct PersonDebtsAndLoans: Identifiable {
    let person: Person
    /// The Person's Loans, the open ones first, in the order Debts & Loans lists them.
    let loans: [LoanOrDebt]
    /// The Person's Debts, the open ones first.
    let debts: [LoanOrDebt]
    /// The Person's Expected reimbursements, the open ones first.
    let expectations: [ExpectedReimbursement]
    /// What they owe the user, one amount per currency (by currency code), none of them zero.
    let owesYou: [Money]
    /// What the user owes them, one amount per currency (by currency code), none of them zero.
    let youOwe: [Money]
    /// How many open Expected reimbursements have no amount, so are in neither figure.
    let openAmountCount: Int
    /// Nothing is outstanding on any of their Loans, Debts or expectations, an open amount included.
    let isSettled: Bool

    var id: PersistentIdentifier { person.persistentModelID }

    init(person: Person, loans: [LoanOrDebt], debts: [LoanOrDebt], expectations: [ExpectedReimbursement]) {
        self.person = person
        self.loans = loans
        self.debts = debts
        self.expectations = expectations
        let openLoans = loans.filter { !$0.isSettled }.map(\.outstanding)
        let expected = ExpectationTotals(expectations)
        owesYou = (openLoans + expected.outstanding).totalsPerCurrency
        youOwe = debts.filter { !$0.isSettled }.map(\.outstanding).totalsPerCurrency
        openAmountCount = expected.openAmountCount
        isSettled = loans.allSatisfy(\.isSettled) && debts.allSatisfy(\.isSettled) && !expectations.contains(where: \.isOpen)
    }

    /// Whether something is flagged as an open amount ("+1 open").
    var hasOpenAmounts: Bool { openAmountCount > 0 }

    /// Whether the row offers Text: the Person has a phone number and something is outstanding to text about
    /// (``TextReminder``). The stored number decides, so no row reads Contacts; the live number is looked up when the user
    /// taps.
    var canText: Bool {
        !isSettled && person.phone?.nilIfBlank != nil
    }
}

/// Debts & Loans as Show by people lists it: every Person with a Loan, a Debt or an Expected reimbursement, the ones with
/// something outstanding first, then a Settled section. Within each, by name.
///
/// A hidden Person (``Person/hide()``) is listed while anything is outstanding with them, so hiding someone never loses
/// track of money; once everything is settled they are left out, as they are from Previous. Loans, Debts and
/// expectations are read from the lists Debts & Loans already holds (``DebtsAndLoans``, ``ExpectedReimbursements`` and
/// its ``ExpectedReimbursements/byPerson``): nothing is fetched here, and a Person is reached through the one Person a Loan
/// or Debt is with, never by walking their transactions (docs/agents/architecture.md).
struct DebtsAndLoansByPerson {
    /// People with something outstanding, including an open amount.
    let open: [PersonDebtsAndLoans]
    /// People with everything settled.
    let settled: [PersonDebtsAndLoans]

    init(_ debtsAndLoans: DebtsAndLoans, _ expectations: ExpectedReimbursements) {
        var people: [ObjectIdentifier: Person] = [:]
        var loans: [ObjectIdentifier: [LoanOrDebt]] = [:]
        var debts: [ObjectIdentifier: [LoanOrDebt]] = [:]
        var owed: [ObjectIdentifier: [ExpectedReimbursement]] = [:]

        for loanOrDebt in debtsAndLoans.open + debtsAndLoans.settled {
            guard let person = loanOrDebt.person else { continue }
            let key = ObjectIdentifier(person)
            people[key] = person
            switch loanOrDebt.kind {
            case .loan: loans[key, default: []].append(loanOrDebt)
            case .debt: debts[key, default: []].append(loanOrDebt)
            }
        }
        for group in expectations.byPerson {
            let key = ObjectIdentifier(group.person)
            people[key] = group.person
            owed[key] = group.expectations
        }

        let listed = people.map { key, person in
            PersonDebtsAndLoans(
                person: person, loans: loans[key] ?? [], debts: debts[key] ?? [], expectations: owed[key] ?? []
            )
        }
        .filter { !$0.person.isHidden || !$0.isSettled }
        .sorted { $0.person.name.localizedStandardCompare($1.person.name) == .orderedAscending }
        open = listed.filter { !$0.isSettled }
        settled = listed.filter(\.isSettled)
    }

    /// Everything Show by people lists, in `context`.
    init(in context: ModelContext) throws {
        self.init(try DebtsAndLoans(in: context), try ExpectedReimbursements(in: context))
    }

    /// `person`'s entry, or `nil` when they are not listed.
    func entry(for person: Person) -> PersonDebtsAndLoans? {
        (open + settled).first { $0.person === person }
    }
}
