import Foundation

/// What checking a sheet's rules found: why it can't save yet, if anything. A sheet enables Save from ``passes`` and
/// says under its fields why it can't save with ``shownProblem``, both from this one check, so it never repeats a rule
/// of its own.
nonisolated struct RuleCheck {
    /// Why it can't be saved as it is, or `nil` when it can.
    let problem: Error?

    /// Runs `check`, which throws the first rule that fails.
    init(_ check: () throws -> Void) {
        do {
            try check()
            problem = nil
        } catch {
            problem = error
        }
    }

    /// Whether every rule passes, so Save can be enabled.
    var passes: Bool { problem == nil }

    /// Why it can't be saved, as the sheet says it under its fields: the ``problem``, unless it only says a field is
    /// still empty (``EmptyFieldError``).
    var shownProblem: Error? {
        guard let problem else { return nil }
        if let empty = problem as? EmptyFieldError, empty.isEmptyField { return nil }
        return problem
    }
}

/// A rule error that can mean a field the person hasn't filled in yet: no name, amount or category so far.
nonisolated protocol EmptyFieldError: Error {
    /// Whether the error only says a field is still empty. A sheet doesn't spell it out, since the empty field shows it
    /// and a new sheet would otherwise open on a complaint.
    var isEmptyField: Bool { get }
}

/// A draft a sheet fills in, which its rules check with `validate()` before anything is saved.
nonisolated protocol ValidatedDraft {
    func validate() throws
}

nonisolated extension ValidatedDraft {
    var check: RuleCheck { RuleCheck(validate) }

    /// Whether every rule passes, so Save can be enabled.
    var canSave: Bool { check.passes }

    /// Why the draft can't be saved, as a sheet says it under its fields (``RuleCheck/shownProblem``).
    var shownProblem: Error? { check.shownProblem }
}

extension TransactionDraft: ValidatedDraft {}
extension TransferDraft: ValidatedDraft {}
extension TransferHalfDraft: ValidatedDraft {}
extension RecurringDraft: ValidatedDraft {}
extension ReimbursementDraft: ValidatedDraft {}
extension BalanceAdjustmentDraft: ValidatedDraft {}
extension WalletDraft: ValidatedDraft {}
extension CardDraft: ValidatedDraft {}

extension TransactionRuleError: EmptyFieldError {
    /// No amount or category yet, or a Loan or Debt with nobody in With, which With's own footer asks for.
    var isEmptyField: Bool { self == .missingAmount || self == .missingCategory || self == .missingWith }
}

extension TransferRuleError: EmptyFieldError {
    var isEmptyField: Bool { self == .missingAmount }
}

extension RecurringRuleError: EmptyFieldError {
    var isEmptyField: Bool { self == .missingName || self == .missingAmount || self == .missingCategory }
}

extension ReimbursementRuleError: EmptyFieldError {
    var isEmptyField: Bool { self == .missingAmount }
}

extension CardRuleError: EmptyFieldError {
    var isEmptyField: Bool { self == .missingName }
}

extension WalletRuleError: EmptyFieldError {
    var isEmptyField: Bool { self == .missingName }
}
