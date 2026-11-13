# Wallet balances come from saved month totals

Adding every wallet's balance up from all ~16,000 transactions of the 16k store on each cold launch kept Home from drawing until the whole store was read ("open Home (cold store)" 592 ms against 174 ms warm, slower again on a phone). So the store keeps, for each wallet and each calendar month, the net of that month's transactions outside Recently Deleted, and a wallet's balance today is the sum of its saved months up to and including this one, minus this month's transactions dated after today (one small read, usually a handful). Every month is saved the same way, the current one included; only reading a balance knows which day it is. Home, the Wallets list and the Wallet selector read balances this way; the Transactions tab and the Report keep reading transactions as before.

The saved totals are never the truth, only a copy of it: they carry a format version, are rebuilt from the transactions on the first launch after an update (about as long as a cold launch took before) or whenever the version changes, are never synced (ADR-0001), and a deleted wallet's totals go with it.

## Keeping them right: a dirty flag, set at the moment of change

- A transaction's wallet, day, amount, Reimbursed total and Recently Deleted mark (`wallet`, `dayRaw`, `amountCents`, `reimbursedCents`, `deletedAt`) can only be changed through one function on `Transaction`. Before it changes them, it marks the wallet-month the transaction was counted in as dirty, and after, the one it is counted in now, so a date moved from March to May marks exactly those two months. Making a transaction goes through it too. The compiler refuses a direct write, so no rule can forget.
- The dirty marks are a model in the same store and go into the same save as the change, so a crash can never keep one without the other.
- Right after each save, the dirty months are recounted and cleared (a month is ~220 transactions: milliseconds, no background work). Any month still dirty, after a crash say, is recounted the next time a balance is read.
- Deleting a transaction for good changes no balance, since it left the balances when it moved to Recently Deleted, so emptying Recently Deleted marks nothing. A Money Lover import, which replaces everything, rebuilds all totals.
- Tests check the saved totals against a full recount after every test, and Debug builds recount once at launch and log a mismatch.

## Considered options

- **Applying each save's change straight to the totals** (incremental maintenance) instead of a dirty flag: any path that forgot its delta would leave a total wrong for good, while a missed dirty flag costs at most a recount, and the single setter makes even that unlikely.
- **Marking months from the save notification**: it reports a transaction only as it is now, so moving one to another month or wallet couldn't name the month it left.
- **Years or quarters on top of months** (a hierarchical rollup): adding ~72 months per wallet takes microseconds; the cost is reading them, which a year layer doesn't save. Years can be added from the months later if a store ever spans decades.
- **Leaving the current month unsaved and reading it live**: it treated one month differently on every write and at each month's turn; subtracting this month's future-dated transactions when reading is one rule in one place.
