import Foundation

/// What the Transfer sheet holds before it is saved: money moved from one of the user's wallets to another.
struct TransferDraft {
    /// The wallet the money leaves: it gets the Outgoing transfer.
    var from: Wallet?
    /// The wallet the money goes to: it gets the Incoming transfer.
    var to: Wallet?
    /// Entered positive.
    var amount = Money(cents: 0)
    var day: CalendarDay
    var note = ""

    init(day: CalendarDay) {
        self.day = day
    }
}

/// Why a transfer can't be saved yet.
nonisolated enum TransferRuleError: Error, Equatable {
    case missingSourceWallet
    case missingDestinationWallet
    /// A transfer moves money between two different wallets.
    case sameWallet
    /// The amount must be above zero.
    case missingAmount
    /// Only an Outgoing or Incoming transfer is edited as a transfer half.
    case notATransferHalf
}

extension TransferRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingSourceWallet: String(localized: "Choose the wallet the money leaves.")
        case .missingDestinationWallet: String(localized: "Choose the wallet the money goes to.")
        case .sameWallet: String(localized: "Choose two different wallets.")
        case .missingAmount: String(localized: "Enter an amount above zero.")
        case .notATransferHalf: String(localized: "Only half of a transfer can be edited here.")
        }
    }
}

extension TransferDraft {
    /// Checks the draft against the transfer rules before anything is saved.
    func validate() throws {
        guard let from else { throw TransferRuleError.missingSourceWallet }
        guard let to else { throw TransferRuleError.missingDestinationWallet }
        guard from != to else { throw TransferRuleError.sameWallet }
        guard amount.cents > 0 else { throw TransferRuleError.missingAmount }
    }

    /// Whether every required field is filled, so Save can be enabled.
    var canSave: Bool { (try? validate()) != nil }
}
