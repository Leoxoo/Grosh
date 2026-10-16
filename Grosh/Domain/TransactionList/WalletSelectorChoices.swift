/// What the Wallet selector lists when opened: the Total, then the wallets that count in it, apart from those left
/// out of it. Each row carries its balance today.
struct WalletSelectorChoices {
    /// One row of the list: what tapping it selects, and that selection's balance today.
    struct Choice: Identifiable {
        let selection: WalletSelection
        /// The Total's balance, or the wallet's in its own currency: the figure the Wallet selector names once the
        /// row is selected.
        let balance: Money

        var id: WalletSelection { selection }
    }

    /// The Total, on its own card above the wallets.
    let total: Choice
    /// The wallets that count in the Total: the "Included in total" section.
    let includedInTotal: [Choice]
    /// The unarchived wallets marked not to count in the Total: the "Not in total" section, absent when it is empty.
    let notInTotal: [Choice]

    /// Lists `wallets`, kept in the order given, with their balances on `today`. Archived wallets and those in
    /// Recently Deleted are left out.
    init(wallets: [Wallet], asOf today: CalendarDay) {
        func choice(_ selection: WalletSelection) -> Choice {
            Choice(selection: selection, balance: selection.balance(asOf: today, wallets: wallets))
        }
        let listed = wallets.filter { !$0.isArchived && !$0.isInRecentlyDeleted }
        total = choice(.total)
        includedInTotal = listed.filter(\.countsInTotal).map { choice(.wallet($0)) }
        notInTotal = listed.filter { !$0.countsInTotal }.map { choice(.wallet($0)) }
    }
}
