# Grosh

A personal finance tracker for one person: where their money sits, what they spent it on, and which card they paid with.

## Language

### Where money lives

**Wallet**:
A place the user's money is held: a checking or savings account, cash, or a brokerage. Its balance is always the sum of its transactions dated today or earlier.
_Avoid_: Account, bank

**Total**:
The combined balance of every unarchived wallet marked "include in total".
_Avoid_: Net worth, all accounts

**Archived wallet**:
A wallet the user no longer uses: left out of the Total and the pickers, but keeping its full history.

**Starting balance**:
The money a wallet already held when it was added, recorded as its first transaction and always excluded from report.
_Avoid_: Initial deposit, opening balance (that's a period term)

**Card**:
The payment card an expense was made with, recorded so the user can reconcile against that card's statement. A Card is only a label the user manages like a category: it holds no balance, carries no debt, and never changes any wallet's balance.
_Avoid_: Payment method, credit account

**Card kind**:
Debit (spends straight from its wallet, no statement) or Credit (has a statement and is paid off in full).

**Paying wallet**:
The wallet a Card belongs to or is paid off from. A Card is only offered on that wallet's transactions.

**Statement date**:
The optional day a Credit card's statement closes. The span between two statement dates is a **statement period**.

### Transactions

**Transaction**:
One dated movement of money into or out of one wallet, filed under one category.
_Avoid_: Entry, record, item

**With**:
The person a transaction involved, such as who the user ate with or who a Loan was given to. A name, not a contact.
_Avoid_: Contact, member, payee

**Event**:
A named occasion a transaction belonged to, such as a trip or a wedding.
_Avoid_: Trip, tag

**Category**:
What a transaction was for. Its category type decides whether the amount adds to or subtracts from the wallet.

**Category type**:
Expense, Income, or Debt/Loan. Expense and Income categories are the user's own; Debt/Loan categories are fixed. The app also keeps categories of its own, such as Starting balance, that are never offered in a picker.

**Parent category** / **Subcategory**:
Categories nest at most two levels deep (e.g. Bills & Utilities → Phone Bill). A transaction may be filed under either level.

**Merge**:
Moving every transaction from one category (or Card) into another, then removing the first.

**Locked category**:
A category the app itself depends on (the transfer pair, Other Income, Other Expense, the four Debt/Loan categories, and Starting balance). It can't be deleted or merged.

**Hidden category**:
A category removed from the picker that keeps its history.
_Avoid_: Inactive, archived (archived is for wallets and Cards)

**Loan**:
Money the user lent to someone else and expects back.
_Avoid_: Debt (that's the other direction)

**Debt**:
Money the user borrowed from someone else and owes back.
_Avoid_: Loan (that's the other direction)

**Debt Collection**:
Money received back against a Loan.

**Repayment**:
Money paid back against a Debt.

**Outstanding**:
How much of a Loan or Debt has not yet been collected or repaid.
_Avoid_: Balance (that word belongs to wallets)

**Settled**:
A Loan or Debt with nothing outstanding. Settling never changes the original transaction; anything paid beyond what was owed is ordinary income or expense.

**Forgive**:
Settling whatever is still outstanding on a Loan or Debt without any money moving, so the forgiven amount appears as ordinary expense or income instead.

**Transfer**:
Money moved between two of the user's own wallets, shown as two linked transactions: an Outgoing transfer and an Incoming transfer. A transfer is never income or spending.
_Avoid_: Move, payment

**Linked transactions**:
Transactions that belong together and are shown to each other as "Related transactions", such as the two halves of a transfer. Editing one offers to update the other.
_Avoid_: Connected, paired

**Balance adjustment**:
A transaction that records the difference between a wallet's recorded balance and its real balance. Its category is the reason (interest earned, stock sold, fees, lost transactions), and it counts in reports like any other transaction. It never needs a Card.
_Avoid_: Correction, reconcile

**Excluded from report**:
A flag that removes a transaction from income and spending statistics. It never removes the transaction from any balance.
_Avoid_: Hidden, ignored

### Time

**Period**:
The span of time the transaction list is showing: a month by default, or Future.

**Time range**:
How long each period of the transaction list is: a day, week, month (the default), quarter or year; all time; or a custom range of days. Only Future and a custom range reach past today.

**Opening balance** / **Ending balance**:
The balance at the start and at the end of a period.

**Future**:
The period holding every transaction dated after today.
