import Foundation

/// The Forgiven mark: the day the user gave up on money owed and their note about it (ADR-0004). A Loan or Debt and an
/// Expected reimbursement carry it the same way; forgiving adds no transaction and moves no balance.
nonisolated protocol ForgivenMarked: AnyObject {
    /// The ``CalendarDay`` (as `yyyymmdd`) it was forgiven on, or `nil` while it isn't.
    var forgivenDayRaw: Int? { get set }
    var forgivenNote: String { get set }
}

nonisolated extension ForgivenMarked {
    /// The day it was forgiven on, or `nil` while it isn't.
    var forgivenDay: CalendarDay? {
        get { forgivenDayRaw.map(CalendarDay.init(rawValue:)) }
        set { forgivenDayRaw = newValue?.rawValue }
    }

    /// Marks it forgiven on `day`, with `note` trimmed. Doesn't save.
    func markForgiven(on day: CalendarDay, note: String) {
        forgivenDay = day
        forgivenNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Takes the mark off. Doesn't save.
    func clearForgivenMark() {
        forgivenDay = nil
        forgivenNote = ""
    }
}

extension Transaction: ForgivenMarked {}

extension ExpectedReimbursement: ForgivenMarked {}
