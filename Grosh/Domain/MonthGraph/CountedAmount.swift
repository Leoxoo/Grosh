/// One of the Month graph's two tabs: Spent, for money going out, or Income, for money coming in.
nonisolated enum SpentOrIncome: CaseIterable, Sendable {
    case spent
    case income
}

/// An amount that counts on the Month graph: toward Spent or Income, on the day it counts.
nonisolated struct CountedAmount {
    let side: SpentOrIncome
    let day: CalendarDay
    /// What it adds to its tab's total. A refund takes away from Spent, so it is below zero there.
    let amount: Money
    /// The category the amount is filed under, which the Category report groups by its parent.
    let category: Category
}

nonisolated extension CountedAmount {
    /// `amount`, as it moves a wallet, filed under `category` on `day`, in a figure written in `currencyCode`. Under an
    /// Expense category it counts toward Spent turned around, so money going out adds to Spent and a refund takes away
    /// from it; under an Income category it counts toward Income as it is. Under any other category, a Debt/Loan one or
    /// one of the app's own such as Starting balance, it counts toward neither. An amount in another currency counts
    /// toward neither too: a figure is in one currency, so a Total holding wallets in two counts those of the one it is
    /// labelled with (``WalletSelection/currencyCode(among:)``), never adding a currency to another. Every
    /// ``CountedAmount`` is made here, so every figure follows this rule.
    fileprivate init?(
        _ amount: Money, filedUnder category: Category?, on day: CalendarDay, countingIn currencyCode: String
    ) {
        guard let category, amount.currencyCode == currencyCode else { return nil }
        switch category.type {
        case .expense:
            self.init(
                side: .spent, day: day, amount: Money(cents: -amount.cents, currencyCode: amount.currencyCode),
                category: category
            )
        case .income:
            self.init(side: .income, day: day, amount: amount, category: category)
        default:
            return nil
        }
    }
}

extension Transaction {
    /// What the transaction counts toward Spent or Income in `selection` (the Total unless another is given), or `nil`
    /// when it counts toward neither. Only the wallets `selection` holds count, only in `currencyCode`, the selection's,
    /// and nothing in Recently Deleted does. Home's Month graph counts the Total.
    ///
    /// A forgiven Loan or Debt counts what was forgiven, on the day it was forgiven and under the category that amount
    /// is filed under (ADR-0004). Its own Exclude from report flag doesn't matter: a Loan or Debt starts excluded, and is
    /// never income or spending itself. Any other transaction counts its net (``Transaction/netCents``) by its
    /// category, as long as it counts in the report. An Expense reimbursed in full counts nothing, and one reimbursed
    /// beyond its amount counts the extra as Income under `otherIncome`, on the Expense's own day. A report reads Other
    /// Income from the store once, with `otherCategory(.income)`, and hands it to every transaction.
    ///
    /// Money paid back into another wallet (ADR-0010) counts where it happened: in the Total the Expense counts its net
    /// less those paybacks (``Transaction/totalViewNetCents``) and the payback itself counts nothing
    /// (``Transaction/isHiddenInTotal``), while a single wallet's report counts the Expense net of what came into that
    /// wallet and a payback into it as money in, under the Reimbursement category.
    func countedAmount(
        in selection: WalletSelection = .total, currencyCode: String, otherIncome: Category
    ) -> CountedAmount? {
        guard CountedAmount.counts(wallet, in: selection, currencyCode: currencyCode) else { return nil }
        return countedAmount(fromCountedWalletIn: selection, currencyCode: currencyCode, otherIncome: otherIncome)
    }

    /// ``countedAmount(in:currencyCode:otherIncome:)`` once its wallet is known to count
    /// (``CountedAmount/counts(_:in:currencyCode:)``), which a whole history asks once per wallet rather than once per
    /// transaction.
    fileprivate func countedAmount(
        fromCountedWalletIn selection: WalletSelection, currencyCode: String, otherIncome: Category
    ) -> CountedAmount? {
        guard !isInRecentlyDeleted else { return nil }
        if let forgiveness {
            return CountedAmount(
                forgiveness.reportAmount, filedUnder: forgiveness.category, on: forgiveness.day, countingIn: currencyCode
            )
        }
        guard countsInReport else { return nil }
        let inTotal = selection == .total
        if inTotal, isHiddenInTotal { return nil }
        let cents = inTotal ? totalViewNetCents : netCents
        // The wallet is in `currencyCode`, so its currency isn't read again.
        let net = Money(cents: cents, currencyCode: currencyCode)
        if category?.type == .expense, amountCents < 0, cents >= 0 {
            guard cents > 0 else { return nil }
            return CountedAmount(net, filedUnder: otherIncome, on: day, countingIn: currencyCode)
        }
        return CountedAmount(net, filedUnder: category, on: day, countingIn: currencyCode)
    }
}

nonisolated extension CountedAmount {
    /// Whether a transaction paid from `wallet` can count in `selection` in a figure written in `currencyCode`: the
    /// selection holds the wallet, and the wallet is in that currency. A Total holding wallets in two currencies counts
    /// those of the one it is labelled with (``WalletSelection/currencyCode(among:)``).
    static func counts(_ wallet: Wallet?, in selection: WalletSelection, currencyCode: String) -> Bool {
        guard let wallet else { return false }
        return selection.includesWallet(wallet) && wallet.currencyCode == currencyCode
    }

    /// What each of `transactions` counts in `selection`, in `currencyCode`
    /// (``Transaction/countedAmount(in:currencyCode:otherIncome:)``), with the transaction it is from, leaving out those
    /// that count nothing. Whether a wallet counts is worked out once for each wallet, not once for each of its
    /// transactions.
    static func counted(
        _ transactions: some Sequence<Transaction>, in selection: WalletSelection, currencyCode: String,
        otherIncome: Category
    ) -> [(transaction: Transaction, amount: CountedAmount)] {
        var walletCounts: [ObjectIdentifier: Bool] = [:]
        var counted: [(transaction: Transaction, amount: CountedAmount)] = []
        for transaction in transactions {
            guard let wallet = transaction.wallet else { continue }
            let id = ObjectIdentifier(wallet)
            let walletCountsHere = walletCounts[id] ?? {
                let counts = counts(wallet, in: selection, currencyCode: currencyCode)
                walletCounts[id] = counts
                return counts
            }()
            guard walletCountsHere, let amount = transaction.countedAmount(
                fromCountedWalletIn: selection, currencyCode: currencyCode, otherIncome: otherIncome
            ) else { continue }
            counted.append((transaction, amount))
        }
        return counted
    }
}

extension ScheduledOccurrence {
    /// What the occurrence would count on the Month graph: what the transaction it makes would count on its due day,
    /// by its Recurring transaction's category, or `nil` when that counts toward neither tab or isn't in `currencyCode`.
    /// Which schedules and wallets count is up to whoever picks the occurrences.
    func countedAmount(in currencyCode: String) -> CountedAmount? {
        CountedAmount(amount, filedUnder: recurring.category, on: day, countingIn: currencyCode)
    }
}
