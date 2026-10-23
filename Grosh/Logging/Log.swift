import Foundation
import os

/// Grosh's loggers. They share one subsystem, the bundle identifier, so Console.app and
/// `log show --predicate 'subsystem == "Leoxo.Grosh"'` list everything Grosh says together, and each area has a category
/// of its own to narrow them. `docs/agents/logging.md` says how to read them.
///
/// A message names what failed and the error, never the data: no amounts, notes, payees, names or account details.
nonisolated enum Log {
    static let subsystem = "Leoxo.Grosh"

    /// Reading and writing the store: saves, fetches and the clean-up at startup.
    static let store = Logger(subsystem: subsystem, category: "Store")
    /// Import from MoneyLover.
    static let importing = Logger(subsystem: subsystem, category: "Import")
    /// Recurring transactions making the transactions that came due.
    static let recurring = Logger(subsystem: subsystem, category: "Recurring")
    /// Scheduling the Loan, Debt and Estimated-amount reminders.
    static let reminders = Logger(subsystem: subsystem, category: "Reminders")
    /// The Report.
    static let reports = Logger(subsystem: subsystem, category: "Reports")
}

nonisolated extension Logger {
    /// Logs that `what` didn't happen, because of `cause`.
    ///
    /// An error Grosh declares is one of its rules refusing a change, such as an invalid draft, a locked or missing
    /// category or a bad import file. The person sees it in an alert and the tests exercise it, so it is logged as
    /// `info`, and so is any error from something the person chose, such as a file, when it is `expected`. Any other
    /// error is the store or the system failing, which should never happen, and is logged as an `error`: `tools/check`
    /// fails a test run that logs one.
    ///
    /// The log names the kind of error and never its message or user info, which can quote the record that failed.
    func failed(_ what: String, _ cause: Error, expected: Bool = false) {
        let isGroshError = String(reflecting: type(of: cause)).hasPrefix("Grosh.")
        let kind: String
        if isGroshError {
            kind = String(describing: cause)
        } else {
            let system = cause as NSError
            kind = "\(system.domain) \(system.code)"
        }
        if isGroshError || expected {
            self.info("\(what, privacy: .public) was refused: \(kind, privacy: .public)")
        } else {
            self.error("\(what, privacy: .public) failed: \(kind, privacy: .public)")
        }
    }

    /// What `work` gives, or `nil` after logging why it failed: a `try?` with the failure on record.
    @discardableResult
    func attempt<Value>(_ what: String, _ work: () throws -> Value) -> Value? {
        do {
            return try work()
        } catch {
            failed(what, error)
            return nil
        }
    }
}

/// The intervals Instruments shows for Grosh, in the category `Performance` of the same subsystem as the logs.
nonisolated enum Signpost {
    static let performance = OSSignposter(subsystem: Log.subsystem, category: "Performance")

    /// Starts the `Launch` interval: the work the app does each time it becomes active, which at launch is all of its
    /// startup work. End it with `end()` in a `defer` straight after, so every way out of the work closes it.
    static func beginLaunch() -> Launch {
        Launch(state: performance.beginInterval("Launch"))
    }

    nonisolated struct Launch {
        fileprivate let state: OSSignpostIntervalState

        func end() {
            Signpost.performance.endInterval("Launch", state)
        }
    }
}
