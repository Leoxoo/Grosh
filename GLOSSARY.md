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

**Wallet selector**:
The control at the top of the Transactions tab and the Report that picks whose transactions they show, the Total or one wallet, and names that selection's balance today. Opening it lists the Total and every unarchived wallet, each with its balance.
_Avoid_: Total menu, Total button

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
The people a transaction involved, such as who the user ate with or who a Loan was given to. A transaction can be with several Persons, except a Loan or Debt, which is with exactly one. Typing a name in With makes the Person or reuses the one who has that name, ignoring case.
_Avoid_: Member, payee

**Person**:
Someone a transaction involved: a name with an optional phone, a hidden flag and the date they were last used. People and places are the same thing, so a restaurant is a Person too. A Person can be linked to an entry in the user's Contacts, which keeps their name and phone up to date (ADR-0009).
_Avoid_: Contact (that is the entry in the Contacts app a Person may be linked to), member, payee

**Previous**:
The section of the With menu that lists every Person who isn't hidden, the one used most recently first. Choosing a Person in With makes them the most recent.

**Hide**:
Swiping a name in Previous and choosing Hide leaves that Person out of Previous. Their name and their place on every transaction stay, so history never changes, and typing their name in With again brings them back.
_Avoid_: Delete, archive (archived is for wallets and Cards)

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
A category the app itself depends on (the transfer pair, Other Income, Other Expense, the four Debt/Loan categories, Starting balance and Reimbursement). It can't be deleted or merged.

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
Settling whatever is still outstanding on a Loan or Debt without any money moving and without adding any transaction. The Loan or Debt is marked **Forgiven** on the day, with an optional note, and can be un-forgiven. The forgiven amount counts in reports as income (a forgiven Debt) or expense (a forgiven Loan) on that day, and never changes any wallet's balance. An Expected reimbursement is forgiven the same way, but as it never counted in a balance or report, forgiving it changes neither.

**Forgiven**:
The mark a forgiven Loan, Debt or Expected reimbursement carries: how much was forgiven, and when. The Loan or Debt's detail tells the whole story, such as borrowed $250, repaid $200, forgiven $50.

**Reminder date**:
The day a Loan or Debt is due, or the day an Expected reimbursement reminds the user to ask for the money. The user gets a notification that day at 09:00, and the Home bell lists it from then until it is settled.
_Avoid_: Alarm, deadline

**Transfer**:
Money moved between two of the user's own wallets, shown as two linked transactions: an Outgoing transfer and an Incoming transfer. A transfer is never income or spending.
_Avoid_: Move, payment

**Linked transactions**:
Transactions that belong together and are shown to each other as "Related transactions", such as the two halves of a transfer. Editing one offers to update the other.
_Avoid_: Connected, paired

**Split**:
Dividing one Expense or Income transaction into several real transactions, one per part, so the user can match a statement that charged it in pieces or file the pieces under different categories. The transaction the user splits from keeps its identity and always shows what is left, while each new part takes its own amount, category, day, note, With and Event; every part shares the wallet and Card. The total is free to change: if the parts no longer add up to the original, the wallet's balance moves by the difference. The parts are Linked transactions but independent: editing one never touches the others, and **Undo split** merges them back into one. Transfers, Balance adjustments, Starting balances, Loans, Debts and their payments, forgiven ones and Scheduled occurrences can't be split.
_Avoid_: Divide, break up

**Reimbursement**:
Money someone paid back against an Expense, kept as an entry on that Expense (an amount, a day and an optional note) and never as a transaction of its own. An Expense can have any number. Its **net** is its amount plus its Reimbursements, shown on its row as `= +3` beside the original amount; the net lands in the Expense's own wallet, on the Expense's own day. The net, not the original amount, counts in balances, the transaction list and every report; only a Card's statement and Card filter total still use the original amount, because that is what the Card was charged. While the net is below zero it counts as Spent under the Expense's own category; at zero it counts as nothing; above zero the Expense counts nothing as Spent and the extra counts as Income under Other Income. Money paid back into a different wallet than the Expense's is not an entry on the Expense but a real transaction in that wallet, a **Reimbursement into another wallet** (ADR-0010): dated the day it was received, filed under the locked Reimbursement category, linked to the Expense like the halves of a Transfer, and counted in its own wallet's balance and report as money in. The Total list hides it and the Expense shows its net there, counting only what was paid into wallets included in the Total; the Expense's own wallet shows the full amount with a note of what was reimbursed to which wallet. The Total report counts the Expense net of those, and a single wallet's report counts only what happened in it. Splitting an Expense that has Reimbursements asks which part each belongs to. See **Expected reimbursement** for the part of an Expense someone is yet to pay back.
_Avoid_: Repayment (that is money paid back against a Debt), refund (that is money back from the seller), payback

**Expected reimbursement**:
The part of an Expense that one Person is yet to pay back ("Owes me"), made with + Owes me on each Person chosen in With, with an optional amount: left blank it is an open amount, shown as `?`, and left out of totals and flagged ("+1 open"). It is a record of its own beside the Expense and never changes any wallet's balance, the transaction list or any report; the Expense stays at its full amount until money comes back. It is listed in Debts & Loans with its own detail, goes to Recently Deleted and back with its Expense, and an edit to the Expense that would break it (making it Income, taking the Person out of With, costing less than what is owed) is refused. It has a Reminder, on by default for a week after the Expense. Record payment turns what comes back into a Reimbursement (or, into another wallet, a Reimbursement into another wallet); an expectation with an amount closes itself once payments cover it, and an open amount is closed by hand. **Forgive** marks it Forgiven and settled, with no accounting effect (ADR-0004, ADR-0010).
_Avoid_: IOU, split bill, Loan (that is money lent outside an Expense)

**Show by people**:
The way Debts & Loans lists one row per Person instead of one per Loan, Debt and Expected reimbursement; **Show by Loan/Debt** is the list as it was, and the choice is remembered. A row shows what the Person owes the user (their Loans plus their Expected reimbursements, combined) and what the user owes them (their Debts) apart, never netted and one amount per currency; an Expected reimbursement with no amount is flagged ("+1 open") and left out of both. People with something outstanding come first, then a Settled section; a hidden Person is listed while anything is outstanding with them. Opening a Person lists their Loans, Debts and Owes me, each opening its own detail (ADR-0009, ADR-0010).
_Avoid_: Contacts list, address book

**Text them**:
Texting a Person about what is owed, from the Text button on their row in Show by people (shown only when they have a phone number) or from the "Text them" action on a reminder notification. It opens the Messages compose sheet to the Person, with a message naming the outstanding amount in the app's money formatting; the user taps Send, and nothing is ever sent without that tap. The number is the linked contact's current one while the contact resolves, otherwise the Person's stored phone. Where texting is unavailable (the simulator, an iPad without Messages) the message can be copied or shared instead.
_Avoid_: Nudge, chase

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
The span of time the transaction list or the Report is showing: a month by default. The transaction list also offers Future; the Report never does.

**Time range**:
How long each period of the transaction list or the Report is: a day, week, month (the default), quarter or year; all time; or a custom range of days. Only Future and the transaction list's custom range reach past today.

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
Home's card with a Spent tab and an Income tab, each naming its month's total so far. The tab shown draws the running total of its month as a line beside a gray line to compare it with and, for the current month, a dotted line for what the Recurring transactions will still add. Every month is laid out as 0–100% of its length, so months of different lengths line up. A strip of months above the card, from the month of the first transaction that counts through this month, picks the month both tabs show; it opens on this month.
_Avoid_: Report this month

**Spent**:
Money going out in a period: its Expense-category transactions that count in the report (net of their Reimbursements), less refunds, plus what was forgiven on Loans. Its counterpart, **Income**, adds up Income-category transactions and what was forgiven on Debts. The Month graph counts the wallets in the Total; the Report counts the Wallet selector's choice.
_Avoid_: Expenses, Expense (that is a Category type)

**Report**:
The full-screen summary opened from Home's Month graph: for the Wallet selector's choice and a period, its opening and ending balances, its Net income and its Category report. Its period never reaches past today.

**Net income**:
Income less Spent for a period: what came in less what went out, not counting transfers, Starting balances, Loan and Debt payments, or anything excluded from report.

**Category report**:
The Report's card splitting Income and Spent into their parent categories, as donuts: the five largest each get a slice, and the rest share one Everything else slice.

**Breakdown** / **Trend**:
The two views of Income or Spent details: Breakdown lists the parent categories with their shares, and Trend bars each Step of the period.

**Everything else**:
The one slice of a Category report donut that holds every parent category beyond the five largest.

**Step**:
One bar or row of Net income and Trend: a day, week, month, quarter or year of the period, cut at the period's edges and at today. A Day or Week range splits into days, a Month into weeks, a Quarter or Year into months, and All time or a custom range by its length.

**Average**:
The gray line a Month graph tab compares its period with unless Last year is on: the mean of the running totals of up to three complete periods of the same length before the period shown. On Home the period is a month; on the Income and Spent details' comparison card it is a week, month, quarter or year. Periods before the one holding the first transaction that counts are left out; a later one with nothing that counts is zero.

**Last year**:
The gray line a Month graph tab shows in place of the Average while its "vs last year" switch is on: the same month 12 months before the month shown. It is there only when that month holds something that counts for the tab; otherwise the switch is greyed out and the tab shows the Average, keeping the switch as it was. One switch serves both tabs, remembered between launches.

**Daily average**:
A period's total divided by the days it covers: through today in the current period, every day of a past one. Income and Spent details show it, except on the Day range.

**Expected by month end**:
On the Income and Spent details the same line reads "Expected by week end", "quarter end" or "year end".
Today's total on a Month graph tab plus what the Recurring transactions still have due through the period's last day: what the month ends at if nothing unscheduled is spent or earned. The graph's projection is not a Scheduled row: it takes every Occurrence left in the month, and changes no balance, report or transaction.

### Feedback

**Keypad**:
The on-screen calculator-style pad for typing an amount, shared by every sheet that takes one. It is not the system keyboard that types text such as a Note or a With.
_Avoid_: Keyboard, numpad

**Success cue**:
The sound and haptic that play together when a new Expense or Income transaction is saved: the picked Chime, with one ending for Income and another for Expense. Editing a transaction, a Transfer, a Loan or Debt, and anything the app makes on its own play none.
_Avoid_: Reward, jingle, celebration

**Chime**:
One of the Success cue's motifs, picked in Settings: Marimba, Glass bells or Bubble pops. All three ship for now, so the user can choose between them on the device itself.
_Avoid_: Sound (a Chime is felt as well as heard), tone, ringtone
