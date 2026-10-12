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

**Card image**:
A photo of the physical card, cropped to a credit card's proportions and shown in place of the Card's symbol. A Card with an image takes its color from the image's average color.
_Avoid_: Card photo, card picture

**Statement date**:
The optional day a Credit card's statement closes, or the month's last day when the month is shorter. A **statement period** runs from the day after one statement date through the next.

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
A Loan or Debt with nothing outstanding, whether it was paid in full or forgiven. Settling never changes the original transaction; anything paid beyond what was owed is ordinary income or expense, which never needs a Card.

**Forgive**:
Settling whatever is still outstanding on a Loan or Debt without any money moving and without adding any transaction. The Loan or Debt is marked **Forgiven** on the day, with an optional note, and can be un-forgiven. The forgiven amount counts in reports as income (a forgiven Debt) or expense (a forgiven Loan) on that day, and never changes any wallet's balance.

**Forgiven**:
The mark a forgiven Loan or Debt carries: how much was forgiven, and when. The Loan or Debt's detail tells the whole story, such as borrowed $250, repaid $200, forgiven $50.

**Reminder date**:
The day a Loan or Debt is due. The user gets a notification that day, and the Home bell lists it from then until it is settled.
_Avoid_: Alarm, deadline

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

**Recently Deleted**:
Where deleted transactions, Recurring transactions and wallets wait for 30 days before they are removed for good. A deleted wallet goes in with all its transactions and Recurring transactions as one item and is restored with them. Until then everything can be restored, and nothing in it counts in any balance or report.
_Avoid_: Trash, recycle bin

**Delete** / **Archive**:
Archiving a wallet keeps it in place but out of the Total and the pickers, and pauses its Recurring transactions. Deleting a wallet, a transaction or a Recurring transaction moves it to Recently Deleted. A Card or category can only be deleted while it has no transactions; otherwise it is merged away or retired (a Card is archived, a category hidden).

### Recurring transactions

**Recurring transaction**:
A schedule that makes a transaction on each of its due days: a name, an amount, a wallet, a category, a Kind, how often it repeats, and when it ends. It is not itself a transaction and counts in no balance or report.
_Avoid_: Template, standing order, subscription (that is one Kind)

**Kind**:
What sort of Recurring transaction it is, kept apart from its category: Bill, Subscription, Purchase or Regular. Every category has a default Kind, Regular unless the user changes it. A subcategory follows its parent's default until the user sets its own, and then keeps it whatever the parent does later.
_Avoid_: Type (that is Category type), section

**Occurrence**:
One due day of a Recurring transaction. An occurrence dated after today is **Scheduled** and shown in Future as a row that is not yet a transaction. On its day it becomes a transaction.

**Bill**:
A Kind for payments that are sure to happen but whose amount is not. A Bill can be marked "amount varies": its transactions start as an **Estimated** amount, the average of the category's recent transactions, and the user is reminded a few days later to enter the real one.

**Estimated**:
The mark on a transaction made by a varying Bill until the user confirms or edits its amount. It counts in balances and reports like any transaction.

**Subscription**:
A Kind for payments with no planned end. It can carry an optional icon, cropped by the user from a screenshot, used for it in place of the category symbol.

**Purchase**:
A Kind for something bought and paid off over time, with an optional total price and a progress of how much has been paid.

**Attached transaction**:
A transaction that belongs to a Recurring transaction, whether it made the transaction itself or the user attached an existing one. The Recurring transaction lists them all.
_Avoid_: Linked (that is Linked transactions)

### Time

**Period**:
The span of time the transaction list is showing: a month by default, or Future.

**Time range**:
How long each period of the transaction list is: a day, week, month (the default), quarter or year; all time; or a custom range of days. Only Future and a custom range reach past today.

**Current period**:
The period of the chosen time range that holds today, so This month by default, or Today, This week, This quarter or This year. The list opens on it and again whenever the time range changes. It is never Future.
_Avoid_: This month (that is only its name when the time range is a month)

**Opening balance** / **Ending balance**:
The balance at the start and at the end of a period.

**Future**:
The period holding every transaction dated after today.

**Lead-in transactions**:
On a Credit card's statement view, the transactions from the two days before the statement period begins, shown muted because they are not part of it. They never count in the statement total unless the user adds one for the moment they are looking.

### Reports

**Month graph**:
Home's Spent and Income cards, each drawing the running total of its month as a line beside a gray line to compare it with and, for the current month, a dotted line for what the Recurring transactions will still add. Every month is laid out as 0–100% of its length, so months of different lengths line up. A strip of months above the cards, from the month of the first transaction that counts through this month, picks the month both show; it opens on this month.
_Avoid_: Report this month

**Spent**:
The Month graph card for money going out: the month's Expense-category transactions in the wallets counted in the Total, less refunds, plus what was forgiven on Loans that month. Its counterpart, the Income card, adds up Income-category transactions and what was forgiven on Debts.
_Avoid_: Expenses, Expense (that is a Category type)

**Average**:
The gray line a Month graph card compares its month with unless Last year is on: the mean of the running totals of up to three complete months before the month shown. Months before the month of the first transaction that counts are left out; a later month with nothing that counts is zero.

**Last year**:
The gray line a Month graph card shows in place of the Average while its "vs last year" switch is on: the same month 12 months before the month shown.

**Expected by month end**:
Today's total on a Month graph card plus what the Recurring transactions still have due through the month's last day: what the month ends at if nothing unscheduled is spent or earned. The graph's projection is not a Scheduled row: it takes every Occurrence left in the month, and changes no balance, report or transaction.
