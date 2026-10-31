import Foundation

/// Every piece of text the app shows, in one place. Change a word here and every screen that shows it follows;
/// translate it in `Localizable.xcstrings`, which Xcode fills from these on each build.
///
/// A constant's English text is also its key in the String Catalog. A function takes the values the text
/// shows (counts, names, formatted amounts and dates), so a translation can move them, and a count can have
/// plural forms.
nonisolated enum Strings {
    /// Words and messages that many screens share.
    enum Common {
        static let cancel: LocalizedStringResource = "Cancel"
        static let done: LocalizedStringResource = "Done"
        static let save: LocalizedStringResource = "Save"
        static let add: LocalizedStringResource = "Add"
        static let edit: LocalizedStringResource = "Edit"
        static let delete: LocalizedStringResource = "Delete"
        static let ok: LocalizedStringResource = "OK"
        static let close: LocalizedStringResource = "Close"
        static let clear: LocalizedStringResource = "Clear"
        static let merge: LocalizedStringResource = "Merge"
        static let archive: LocalizedStringResource = "Archive"
        static let unarchive: LocalizedStringResource = "Unarchive"
        static let archived: LocalizedStringResource = "Archived"
        static let restore: LocalizedStringResource = "Restore"
        static let duplicate: LocalizedStringResource = "Duplicate"
        static let hide: LocalizedStringResource = "Hide"
        static let show: LocalizedStringResource = "Show"
        static let unhide: LocalizedStringResource = "Unhide"
        static let remove: LocalizedStringResource = "Remove"
        static let none: LocalizedStringResource = "None"
        static let choose: LocalizedStringResource = "Choose"
        static let any: LocalizedStringResource = "Any"
        static let name: LocalizedStringResource = "Name"
        static let amount: LocalizedStringResource = "Amount"
        static let date: LocalizedStringResource = "Date"
        static let wallet: LocalizedStringResource = "Wallet"
        static let category: LocalizedStringResource = "Category"
        static let card: LocalizedStringResource = "Card"
        static let note: LocalizedStringResource = "Note"
        static let with: LocalizedStringResource = "With"
        static let event: LocalizedStringResource = "Event"
        static let type: LocalizedStringResource = "Type"
        static let kind: LocalizedStringResource = "Kind"
        static let color: LocalizedStringResource = "Color"
        static let icon: LocalizedStringResource = "Icon"
        static let from: LocalizedStringResource = "From"
        static let to: LocalizedStringResource = "To"
        static let total: LocalizedStringResource = "Total"
        static let balance: LocalizedStringResource = "Balance"
        static let transactions: LocalizedStringResource = "Transactions"
        static let income: LocalizedStringResource = "Income"
        static let spent: LocalizedStringResource = "Spent"
        static let expense: LocalizedStringResource = "Expense"
        static let day: LocalizedStringResource = "Day"
        static let error: LocalizedStringResource = "Error"
        static let hidden: LocalizedStringResource = "Hidden"
        static let on: LocalizedStringResource = "On"
        static let off: LocalizedStringResource = "Off"
        static let uncategorized: LocalizedStringResource = "Uncategorized"
        static let cantBeUndone: LocalizedStringResource = "This can't be undone."
        static let enterAmountAboveZero: LocalizedStringResource = "Enter an amount above zero."
        static let chooseAWallet: LocalizedStringResource = "Choose a wallet."
        static let chooseACategory: LocalizedStringResource = "Choose a category."
        static let chooseTwoDifferentWallets: LocalizedStringResource = "Choose two different wallets."
        static let excludeFromReport: LocalizedStringResource = "Exclude from report"
        static let excludedFromReport: LocalizedStringResource = "Excluded from report"
        static let excludedFromReportFooter: LocalizedStringResource = "Left out of income and spending. It still counts in the wallet's balance."
        static let includedInTotal: LocalizedStringResource = "Included in Total"
        static let notInTotal: LocalizedStringResource = "Not in Total"
        static let noTransactions: LocalizedStringResource = "No Transactions"
        static let nothingRecordedInPeriod: LocalizedStringResource = "Nothing was recorded in this period."
        static let addWalletFirst: LocalizedStringResource = "Add a wallet first, in Account → Wallets."
        static let onlyThisOne: LocalizedStringResource = "Only This One"
        static let searchPrompt: LocalizedStringResource = "Note, category or amount"
        static let timeRange: LocalizedStringResource = "Time Range"
        static let custom: LocalizedStringResource = "Custom"
        static let customEllipsis: LocalizedStringResource = "Custom…"
        static let openingBalance: LocalizedStringResource = "Opening balance"
        static let endingBalance: LocalizedStringResource = "Ending balance"
        static let difference: LocalizedStringResource = "Difference"
        static let settled: LocalizedStringResource = "Settled"
        static let forgiven: LocalizedStringResource = "Forgiven"
        static let reimbursements: LocalizedStringResource = "Reimbursements"
        static let comingSoon: LocalizedStringResource = "Coming Soon"
        static let step: LocalizedStringResource = "Step"
        static let line: LocalizedStringResource = "Line"
        static let zero: LocalizedStringResource = "Zero"
        static let previousDay: LocalizedStringResource = "Previous Day"
        static let nextDay: LocalizedStringResource = "Next Day"
        static func deleteNamed(_ name: String) -> LocalizedStringResource { "Delete “\(name)”?" }
        static func archivedName(_ name: String) -> LocalizedStringResource { "\(name) (Archived)" }
    }

    /// Names of tabs and screens, used for titles and the rows that open them.
    enum Screens {
        static let home: LocalizedStringResource = "Home"
        static let budgets: LocalizedStringResource = "Budgets"
        static let account: LocalizedStringResource = "Account"
        static let wallets: LocalizedStringResource = "Wallets"
        static let categories: LocalizedStringResource = "Categories"
        static let cards: LocalizedStringResource = "Cards"
        static let debtsAndLoans: LocalizedStringResource = "Debts & Loans"
        static let recentlyDeleted: LocalizedStringResource = "Recently Deleted"
        static let importFromMoneyLover: LocalizedStringResource = "Import from MoneyLover"
        static let exportCSV: LocalizedStringResource = "Export CSV"
        static let settings: LocalizedStringResource = "Settings"
        static let report: LocalizedStringResource = "Report"
        static let search: LocalizedStringResource = "Search"
        static let filters: LocalizedStringResource = "Filters"
        static let recurringTransactions: LocalizedStringResource = "Recurring transactions"
        static let currency: LocalizedStringResource = "Currency"
        static let reminders: LocalizedStringResource = "Reminders"
        static let netIncome: LocalizedStringResource = "Net income"
    }

    /// Names of periods and time ranges.
    enum Periods {
        static let today: LocalizedStringResource = "Today"
        static let yesterday: LocalizedStringResource = "Yesterday"
        static let thisWeek: LocalizedStringResource = "This week"
        static let lastWeek: LocalizedStringResource = "Last week"
        static let thisMonth: LocalizedStringResource = "This month"
        static let lastMonth: LocalizedStringResource = "Last month"
        static let thisQuarter: LocalizedStringResource = "This quarter"
        static let lastQuarter: LocalizedStringResource = "Last quarter"
        static let lastYear: LocalizedStringResource = "Last year"
        static let thisYear: LocalizedStringResource = "This year"
        static let allTime: LocalizedStringResource = "All time"
        static let future: LocalizedStringResource = "Future"
        static let week: LocalizedStringResource = "Week"
        static let month: LocalizedStringResource = "Month"
        static let quarter: LocalizedStringResource = "Quarter"
        static let year: LocalizedStringResource = "Year"
        static let all: LocalizedStringResource = "All"
    }

    /// The Home tab and its Month graph.
    enum Home {
        static let addAWallet: LocalizedStringResource = "Add a wallet"
        static let myWallets: LocalizedStringResource = "My Wallets"
        static let seeAll: LocalizedStringResource = "See all"
        static let showTotal: LocalizedStringResource = "Show Total"
        static let hideTotal: LocalizedStringResource = "Hide Total"
        static let totalBalance: LocalizedStringResource = "Total balance"
        static let seeReports: LocalizedStringResource = "See reports"
        static let vsLastYear: LocalizedStringResource = "vs last year"
        static let recentTransactions: LocalizedStringResource = "Recent transactions"
        static let recentTransactionsEmpty: LocalizedStringResource = "Transactions you add show up here."
        static let dayEnd: LocalizedStringResource = "day end"
        static let weekEnd: LocalizedStringResource = "week end"
        static let monthEnd: LocalizedStringResource = "month end"
        static let quarterEnd: LocalizedStringResource = "quarter end"
        static let yearEnd: LocalizedStringResource = "year end"
        static let end: LocalizedStringResource = "end"
        static let average: LocalizedStringResource = "Average"
        static func expected(_ amount: String) -> LocalizedStringResource { "Expected \(amount)" }
        static func scheduledExpectedBy(_ end: String, _ amount: String) -> LocalizedStringResource { "Scheduled · Expected by \(end) \(amount)" }
    }

    /// Adding, editing, splitting, listing and deleting transactions.
    enum Transactions {
        static let addTransaction: LocalizedStringResource = "Add Transaction"
        static let editTransaction: LocalizedStringResource = "Edit Transaction"
        static let newTransaction: LocalizedStringResource = "New Transaction"
        static let transaction: LocalizedStringResource = "Transaction"
        static let transactionDeleted: LocalizedStringResource = "Transaction Deleted"
        static let couldntSave: LocalizedStringResource = "Couldn't Save Transaction"
        static let missingCard: LocalizedStringResource = "Choose the Card this expense was paid with."
        static let missingWith: LocalizedStringResource = "Choose who you lent to or borrowed from in With."
        static let tooManyWith: LocalizedStringResource = "A Loan or Debt is with one person. Choose one in With."
        static let notAStartingBalance: LocalizedStringResource = "Only a wallet's Starting balance can be edited here."
        static let forgivenLockFooter: LocalizedStringResource = "It's forgiven, so it keeps its amount, wallet and category until it's un-forgiven."
        static let cardRequiredFooter: LocalizedStringResource = "Choose the Card this expense was paid with. Expenses need a Card when their wallet has one."
        static let addMoreDetails: LocalizedStringResource = "Add more details"
        static let comingSoon: LocalizedStringResource = "Coming soon"
        static let location: LocalizedStringResource = "Location"
        static let withRequiredFooter: LocalizedStringResource = "A Loan or Debt needs a With: who you lent to or borrowed from."
        static let enterAmount: LocalizedStringResource = "Enter Amount"
        static let estimatedFooter: LocalizedStringResource = "This amount is the average of recent transactions in its category. Enter the real amount to confirm it."
        static let duplicateFooter: LocalizedStringResource = "Duplicate opens a new transaction with the same details, dated today."
        static let customRange: LocalizedStringResource = "Custom Range"
        static let projectedBalance: LocalizedStringResource = "Projected balance"
        static let relatedTransactions: LocalizedStringResource = "Related transactions"
        static let undoSplit: LocalizedStringResource = "Undo Split"
        static let undoSplitQuestion: LocalizedStringResource = "Undo this split?"
        static let undoSplitMessage: LocalizedStringResource = "The parts merge back into the original, which takes the sum of their amounts."
        static let couldntUndoSplit: LocalizedStringResource = "Couldn't Undo Split"
        static let scheduled: LocalizedStringResource = "Scheduled"
        static let selectWallet: LocalizedStringResource = "Select Wallet"
        static let thisTransaction: LocalizedStringResource = "This transaction"
        static let thisTransactionTitle: LocalizedStringResource = "This Transaction"
        static let newParts: LocalizedStringResource = "New parts"
        static let addPart: LocalizedStringResource = "Add Part"
        static let split: LocalizedStringResource = "Split"
        static let newPart: LocalizedStringResource = "New Part"
        static let editPart: LocalizedStringResource = "Edit Part"
        static let couldntSplit: LocalizedStringResource = "Couldn't Split Transaction"
        static let balanceChange: LocalizedStringResource = "Balance change"
        static let leaveSomeFooter: LocalizedStringResource = "Leave some on this transaction, or type over its amount to raise the total."
        static let originalShowsRestFooter: LocalizedStringResource = "This transaction shows what the other parts leave of the total."
        static let chooseAPart: LocalizedStringResource = "Choose a part"
        static let chooseReimbursementPartFooter: LocalizedStringResource = "Choose the part each Reimbursement was paid back against."
        static let differentAmountChangesTotal: LocalizedStringResource = "Typing a different amount changes the total."
        static let notSplittable: LocalizedStringResource = "Only an ordinary expense or income can be split."
        static let noParts: LocalizedStringResource = "Add at least one part."
        static let splitMissingAmount: LocalizedStringResource = "Give every part an amount above zero, and leave some on the original."
        static let splitMissingCategory: LocalizedStringResource = "Choose a category for every part."
        static let unassignedReimbursement: LocalizedStringResource = "Choose a part for every reimbursement."
        static let notSplit: LocalizedStringResource = "This transaction has no other parts to merge."
        static let editStartingBalance: LocalizedStringResource = "Edit Starting Balance"
        static let startingBalanceFooter: LocalizedStringResource = "The money this wallet held when it was added, below zero if it started in debt. It is always excluded from report."
        static let couldntSaveStartingBalance: LocalizedStringResource = "Couldn't Save Starting Balance"
        static let deleteTransaction: LocalizedStringResource = "Delete Transaction"
        static let couldntDelete: LocalizedStringResource = "Couldn't Delete Transaction"
        static let couldntDeleteSeveral: LocalizedStringResource = "Couldn't Delete Transactions"
        static let deleteRelatedToo: LocalizedStringResource = "Delete the related transactions too?"
        static let deleteThisTransaction: LocalizedStringResource = "Delete this transaction?"
        static let deleteBoth: LocalizedStringResource = "Delete Both"
        static let futureEmpty: LocalizedStringResource = "Transactions dated after today show up here."
        static let selectTransactions: LocalizedStringResource = "Select Transactions"
        static let more: LocalizedStringResource = "More"
        static let viewByCategory: LocalizedStringResource = "View by Category"
        static let select: LocalizedStringResource = "Select"
        static let noTransactionSelected: LocalizedStringResource = "No Transaction Selected"
        static let selectTransactionDescription: LocalizedStringResource = "Select a transaction to see its details."
        static let estimated: LocalizedStringResource = "Estimated"
        static let estimatedShort: LocalizedStringResource = "est."
        static func paymentsLockFooter(_ paid: String) -> LocalizedStringResource { "Its payments keep the wallet and category. The amount can't be less than the \(paid) already paid back." }
        static func backTo(_ title: String) -> LocalizedStringResource { "Back to \(title)" }
        static func totalWas(_ total: String, _ was: String) -> LocalizedStringResource { "\(total) (was \(was))" }
        static func walletBalanceChanges(_ wallet: String) -> LocalizedStringResource { "\(wallet)'s balance changes by the difference." }
        static func leavesOnOriginal(_ amount: String) -> LocalizedStringResource { "Leaves \(amount) on the transaction being split." }
        static func deleteCountQuestion(_ count: Int) -> LocalizedStringResource { "Delete \(count) transactions?" }
        static func hasRelated(_ count: Int) -> LocalizedStringResource { "This transaction has \(count) related transactions." }
        static func selectedHaveRelated(_ count: Int) -> LocalizedStringResource { "The selected transactions have \(count) related transactions that aren't selected." }
        static func onlyThese(_ count: Int) -> LocalizedStringResource { "Only These \(count)" }
        static func deleteCount(_ count: Int) -> LocalizedStringResource { "Delete \(count) Transactions" }
        static func deleteAll(_ count: Int) -> LocalizedStringResource { "Delete All \(count)" }
        static func selectedCount(_ count: Int) -> LocalizedStringResource { "\(count) Selected" }
    }

    /// Transfers between wallets.
    enum Transfers {
        static let transfer: LocalizedStringResource = "Transfer"
        static let missingSourceWallet: LocalizedStringResource = "Choose the wallet the money leaves."
        static let missingDestinationWallet: LocalizedStringResource = "Choose the wallet the money goes to."
        static let notATransferHalf: LocalizedStringResource = "Only half of a transfer can be edited here."
        static let twoWalletsNeeded: LocalizedStringResource = "A transfer needs two wallets. Add another in Account → Wallets."
        static let footer: LocalizedStringResource = "Recorded as an Outgoing transfer and an Incoming transfer, linked to each other. A transfer is never income or spending, and the Total doesn't change."
        static let couldntSave: LocalizedStringResource = "Couldn't Save Transfer"
        static let halfFooter: LocalizedStringResource = "Changing the amount or date asks whether to change the other half of the transfer too."
        static let updateOtherHalfQuestion: LocalizedStringResource = "Update the other half of the transfer too?"
        static let updateBoth: LocalizedStringResource = "Update Both"
        static let onlyThisOneFooter: LocalizedStringResource = "Only This One leaves the two halves different, as when a fee was taken."
    }

    /// Adjusting a wallet's balance to what it really holds.
    enum BalanceAdjustment {
        static let adjustBalance: LocalizedStringResource = "Adjust Balance"
        static let cantAdjust: LocalizedStringResource = "Can't Adjust Balance"
        static let categoriesMissing: LocalizedStringResource = "The Other Income and Other Expense categories are missing."
        static let couldntAdjust: LocalizedStringResource = "Couldn't Adjust Balance"
        static let recordedBalance: LocalizedStringResource = "Recorded balance"
        static let realBalance: LocalizedStringResource = "Real balance"
        static let typeRealBalanceFooter: LocalizedStringResource = "Type what the wallet really holds on this date. The difference is recorded as one transaction."
        static let reason: LocalizedStringResource = "Reason"
        static let alreadyMatchesFooter: LocalizedStringResource = "The recorded balance already matches. Type the real balance to adjust it."
        static let reasonFooter: LocalizedStringResource = "The reason is any Income category when the balance goes up, or any Expense category when it goes down. It counts in reports unless excluded, and never needs a Card."
        static let balanceAdjustment: LocalizedStringResource = "Balance adjustment"
        static let balanceChangeFooter: LocalizedStringResource = "What the wallet's transactions added up to, and its actual balance after this adjustment."
        static let changedTo: LocalizedStringResource = "to"
        static let enterRealBalance: LocalizedStringResource = "Enter what the wallet really holds."
        static let alreadyThisBalance: LocalizedStringResource = "The wallet already has this balance."
        static let reasonCategoryType: LocalizedStringResource = "Choose an Income category when the balance goes up, or an Expense category when it goes down."
    }

    /// Wallets: adding, editing, archiving and deleting them.
    enum Wallets {
        static let missingName: LocalizedStringResource = "Give the wallet a name."
        static let deleteThisWallet: LocalizedStringResource = "Delete this wallet?"
        static let deleteWallet: LocalizedStringResource = "Delete Wallet"
        static let couldntDelete: LocalizedStringResource = "Couldn't Delete Wallet"
        static let includeInTotal: LocalizedStringResource = "Include in Total"
        static let includeFooter: LocalizedStringResource = "The Total on Home adds up the wallets that are included."
        static let adjustBalanceFooter: LocalizedStringResource = "Type what the wallet really holds; the difference is recorded as one transaction."
        static let unarchiveWallet: LocalizedStringResource = "Unarchive Wallet"
        static let archiveWallet: LocalizedStringResource = "Archive Wallet"
        static let archivedFooter: LocalizedStringResource = "An archived wallet leaves the Total and the pickers but keeps its transactions. Its Recurring transactions pause until it is unarchived."
        static let addWallet: LocalizedStringResource = "Add Wallet"
        static let editWallet: LocalizedStringResource = "Edit Wallet"
        static let couldntSave: LocalizedStringResource = "Couldn't Save Wallet"
        static let currentBalance: LocalizedStringResource = "Current balance"
        static let startingBalance: LocalizedStringResource = "Starting balance"
        static let amountExample: LocalizedStringResource = "Enter an amount such as 1,250.00."
        static let startingBalanceFooter: LocalizedStringResource = "The money this wallet holds now. It becomes the wallet's first transaction and is excluded from report."
        static let reorderFooter: LocalizedStringResource = "Drag to reorder. Home and every wallet picker use this order."
        static let archivedSectionFooter: LocalizedStringResource = "Archived wallets are left out of the Total and the pickers. Their transactions are kept."
        static let noWallets: LocalizedStringResource = "No Wallets"
        static let noWalletsDescription: LocalizedStringResource = "Add a wallet for each place you keep money."
        static let couldntChange: LocalizedStringResource = "Couldn't Change Wallet"
        static func deleteMessage(_ name: String, _ days: Int) -> LocalizedStringResource { "“\(name)” and all its transactions and Recurring transactions will be deleted and moved to Recently Deleted, where they can be restored for \(days) days." }
        static func deletingFooter(_ days: Int) -> LocalizedStringResource { "Deleting moves the wallet, its transactions and its Recurring transactions to Recently Deleted for \(days) days." }
    }

    /// Cards: the label for what an expense was paid with.
    enum Cards {
        static let missingName: LocalizedStringResource = "Give the Card a name."
        static let missingPayingWallet: LocalizedStringResource = "Choose the wallet this Card is paid from."
        static let statementDateRequiresCredit: LocalizedStringResource = "Only Credit cards have a statement date."
        static let statementDayOutOfRange: LocalizedStringResource = "A statement date is a day from 1 to 31."
        static let invalidLastFourDigits: LocalizedStringResource = "Enter all 4 last digits, or leave them blank."
        static let mergeIntoItself: LocalizedStringResource = "Choose another Card to merge into."
        static let mergeIntoAnotherWallet: LocalizedStringResource = "Choose a Card paid from the same wallet."
        static let mergeIntoArchived: LocalizedStringResource = "Unarchive that Card before merging into it."
        static let hasTransactions: LocalizedStringResource = "This Card paid for transactions. Merge it into another Card to remove it."
        static let payingWalletHasTransactions: LocalizedStringResource = "This Card paid for transactions, so its paying wallet can't change."
        static let payingWallet: LocalizedStringResource = "Paying wallet"
        static let lastFourDigits: LocalizedStringResource = "Last 4 digits (optional)"
        static let addWalletFirstFooter: LocalizedStringResource = "Add a wallet first. A Card is paid from a wallet and only offered on its transactions."
        static let onlyALabelFooter: LocalizedStringResource = "A Card is only a label: it never changes any balance. It is offered on its paying wallet's transactions."
        static let imageColorFooter: LocalizedStringResource = "A Card with an image takes its color from the image."
        static let addCard: LocalizedStringResource = "Add Card"
        static let editCard: LocalizedStringResource = "Edit Card"
        static let couldntSave: LocalizedStringResource = "Couldn't Save Card"
        static let statementDate: LocalizedStringResource = "Statement date"
        static let closesOnThe: LocalizedStringResource = "Closes on the"
        static let statementDayFooter: LocalizedStringResource = "The statement closes on this day each month, or on the month's last day when the month is shorter."
        static let addStatementDayFooter: LocalizedStringResource = "Add the day this card's statement closes to see its transactions by statement period."
        static let unarchiveCard: LocalizedStringResource = "Unarchive Card"
        static let archiveCard: LocalizedStringResource = "Archive Card"
        static let mergeIntoAnother: LocalizedStringResource = "Merge into Another Card…"
        static let deleteCard: LocalizedStringResource = "Delete Card"
        static let archivedMergeFooter: LocalizedStringResource = "An archived Card leaves the pickers but stays on its transactions. To remove this Card, merge it into another one: its transactions move there."
        static let archivedFooter: LocalizedStringResource = "An archived Card leaves the pickers but stays on its transactions."
        static let onlyALabelListFooter: LocalizedStringResource = "A Card is only a label for what an expense was paid with. It never changes any balance."
        static let archivedSectionFooter: LocalizedStringResource = "Archived Cards leave the pickers but stay on their transactions."
        static let noCards: LocalizedStringResource = "No Cards"
        static let noCardsDescription: LocalizedStringResource = "Add the cards you pay with to see which one each expense went on."
        static let couldntChange: LocalizedStringResource = "Couldn't Change Card"
        static let mergeEmpty: LocalizedStringResource = "A Card merges into another unarchived Card paid from the same wallet."
        static let theCardYouPick: LocalizedStringResource = "the Card you pick"
        static let debit: LocalizedStringResource = "Debit"
        static let credit: LocalizedStringResource = "Credit"
        static let cardRemoved: LocalizedStringResource = "Card Removed"
        static let cardRemovedDescription: LocalizedStringResource = "It was merged into another Card or deleted."
        static let statementTotal: LocalizedStringResource = "Statement total"
        static let statementPeriodFooter: LocalizedStringResource = "A statement period runs from the day after one statement date through the next."
        static let nothingPaidInPeriod: LocalizedStringResource = "Nothing was paid with this Card in this period."
        static let previousStatementSection: LocalizedStringResource = "Previous statement"
        static let removeFromStatementTotal: LocalizedStringResource = "Remove from Statement Total"
        static let addToStatementTotal: LocalizedStringResource = "Add to Statement Total"
        static let previousStatement: LocalizedStringResource = "Previous Statement"
        static let previousMonth: LocalizedStringResource = "Previous Month"
        static let currentStatement: LocalizedStringResource = "Current statement"
        static let statementPeriod: LocalizedStringResource = "Statement period"
        static let nextStatement: LocalizedStringResource = "Next Statement"
        static let nextMonth: LocalizedStringResource = "Next Month"
        static func statementOnThe(_ day: String) -> LocalizedStringResource { "Statement on the \(day)" }
        static func includesFromPreviousStatement(_ count: Int) -> LocalizedStringResource { "Includes \(count) from the previous statement" }
        static func previousStatementFooter(_ days: Int) -> LocalizedStringResource { "From the \(days) days before this statement, as entries aren't always dated as on the statement. They're not in its total; tap + to add one for now." }
    }

    /// Categories: adding, editing, hiding, merging and picking them.
    enum Categories {
        static let lockedError: LocalizedStringResource = "The app relies on this category. Only its icon can be changed."
        static let differentType: LocalizedStringResource = "Choose a category of the same type."
        static let sameCategory: LocalizedStringResource = "Choose a different category."
        static let tooDeep: LocalizedStringResource = "Categories nest at most two levels deep."
        static let hasTransactions: LocalizedStringResource = "This category has transactions. Merge it into another category instead."
        static let nameRequired: LocalizedStringResource = "Give the category a name."
        static let nameTaken: LocalizedStringResource = "Another category of this type already has this name."
        static let fixedType: LocalizedStringResource = "Only Expense and Income categories can be added or moved."
        static let addCategory: LocalizedStringResource = "Add Category"
        static let editCategory: LocalizedStringResource = "Edit Category"
        static let couldntSave: LocalizedStringResource = "Couldn't Save Category"
        static let parent: LocalizedStringResource = "Parent"
        static let typeLockedFooter: LocalizedStringResource = "This category has transactions, so its type can't change."
        static let topLevelFooter: LocalizedStringResource = "A category with subcategories stays at the top level."
        static let kindFooter: LocalizedStringResource = "New Recurring transactions in this category start as this Kind. Existing ones keep theirs."
        static let unhideCategory: LocalizedStringResource = "Unhide Category"
        static let hideCategory: LocalizedStringResource = "Hide Category"
        static let mergeIntoAnother: LocalizedStringResource = "Merge into Another Category…"
        static let deleteCategory: LocalizedStringResource = "Delete Category"
        static let hiddenFooter: LocalizedStringResource = "Hidden categories leave the picker but stay on their transactions."
        static let cantDeleteFooter: LocalizedStringResource = "This category has transactions, so it can't be deleted. Merge it into another category instead."
        static let debtLoan: LocalizedStringResource = "Debt/Loan"
        static let system: LocalizedStringResource = "System"
        static let couldntChange: LocalizedStringResource = "Couldn't Change Category"
        static let debtLoanFooter: LocalizedStringResource = "Debt/Loan categories are fixed. You can change their icons."
        static let showHidden: LocalizedStringResource = "Show hidden categories"
        static let appsOwn: LocalizedStringResource = "The app's own categories"
        static let appsOwnFooter: LocalizedStringResource = "The app files transactions under these itself, such as a new wallet's Starting balance. You can change their icons."
        static let reorderFooter: LocalizedStringResource = "Drag to reorder. A category's subcategories move with it. When you pick a category, the ones used most in the last month still come first."
        static let locked: LocalizedStringResource = "Locked"
        static let theCategoryYouPick: LocalizedStringResource = "the category you pick"
        static let searchCategories: LocalizedStringResource = "Search categories"
        static func subcategoriesDeletedToo(_ count: Int) -> LocalizedStringResource { "Its \(count) subcategories are deleted too. This can't be undone." }
        static func sameAsParent(_ parent: String, _ kind: String) -> LocalizedStringResource { "Same as \(parent) (\(kind))" }
        static func nothingToMergeInto(_ type: String) -> LocalizedStringResource { "There's no other \(type) category this one can be merged into." }
        static func subcategoriesMoveUnder(_ count: Int) -> LocalizedStringResource { " and its \(count) subcategories move under it" }
        static func missingLockedCategory(_ name: String) -> LocalizedStringResource { "Grosh can't do this without its “\(name)” category, which is missing." }
    }

    /// Merging a Card or a category into another.
    enum Merge {
        static let mergeInto: LocalizedStringResource = "Merge into"
        static let nothingToMergeInto: LocalizedStringResource = "Nothing to Merge Into"
        static let couldntMerge: LocalizedStringResource = "Couldn't Merge"
        static func title(_ name: String) -> LocalizedStringResource { "Merge “\(name)”" }
        static func confirmation(_ source: String, _ target: String) -> LocalizedStringResource { "Merge “\(source)” into “\(target)”?" }
        static func itsTransactionMovesTo(_ destination: String) -> LocalizedStringResource { "Its transaction moves to \(destination)" }
        static func itsTransactionsMoveTo(_ count: Int, _ destination: String) -> LocalizedStringResource { "Its \(count) transactions move to \(destination)" }
        static func thenRemoved(_ name: String) -> LocalizedStringResource { ". Then “\(name)” is removed." }
    }

    /// Loans and Debts: payments, forgiving and reminders.
    enum DebtsLoans {
        static let notALoanOrDebt: LocalizedStringResource = "Only a Loan or a Debt can be paid back or forgiven."
        static let nothingOutstanding: LocalizedStringResource = "Nothing is outstanding any more."
        static let overpaymentCategoryType: LocalizedStringResource = "Choose an Income category for money that comes in, or an Expense category for money that goes out."
        static let wrongPaymentCategory: LocalizedStringResource = "A Loan is paid back with Debt Collections, and a Debt with Repayments."
        static let paymentsLock: LocalizedStringResource = "Its payments keep this Loan or Debt in its wallet and category."
        static let amountBelowPaid: LocalizedStringResource = "The amount can't be less than what has already been paid back."
        static let notForgiven: LocalizedStringResource = "This Loan or Debt isn't forgiven."
        static let unforgiveFirst: LocalizedStringResource = "Un-forgive this Loan or Debt before changing its amount, wallet or category."
        static let open: LocalizedStringResource = "Open"
        static let show: LocalizedStringResource = "Show"
        static let showByPeople: LocalizedStringResource = "Show by people"
        static let showByLoanOrDebt: LocalizedStringResource = "Show by Loan/Debt"
        static let noDebtsOrLoans: LocalizedStringResource = "No Debts or Loans"
        static let noDebtsOrLoansDescription: LocalizedStringResource = "Add a Loan or a Debt on the Debt/Loan tab of Add Transaction, or + Owes me on an expense's With."
        static let noDueReminders: LocalizedStringResource = "No Due Reminders"
        static let noDueRemindersDescription: LocalizedStringResource = "A Loan, Debt, Owes me or estimated amount shows here once its reminder date comes."
        static let cantForgive: LocalizedStringResource = "Can't Forgive"
        static let onlyLoanOrDebtForgiven: LocalizedStringResource = "Only a Loan or a Debt can be forgiven."
        static let forgiveTheRest: LocalizedStringResource = "Forgive the Rest"
        static let forgive: LocalizedStringResource = "Forgive"
        static let couldntForgive: LocalizedStringResource = "Couldn't Forgive"
        static let loan: LocalizedStringResource = "Loan"
        static let debt: LocalizedStringResource = "Debt"
        static let lentTo: LocalizedStringResource = "Lent To"
        static let borrowedFrom: LocalizedStringResource = "Borrowed From"
        static let loanPaymentsFooter: LocalizedStringResource = "Payments are recorded as Debt Collections. The Loan itself never changes."
        static let debtPaymentsFooter: LocalizedStringResource = "Payments are recorded as Repayments. The Debt itself never changes."
        static let loanRecordPaymentFooter: LocalizedStringResource = "Recorded as a Debt Collection in the Loan's wallet, excluded from report. The Loan itself doesn't change."
        static let debtRecordPaymentFooter: LocalizedStringResource = "Recorded as a Repayment from the Debt's wallet, excluded from report. The Debt itself doesn't change."
        static let loanOverpaymentFooter: LocalizedStringResource = "What's paid above the outstanding amount is recorded as income and counts in reports."
        static let debtOverpaymentFooter: LocalizedStringResource = "What's paid above the outstanding amount is recorded as an expense and counts in reports."
        static let loanForgiveFooter: LocalizedStringResource = "Marks the Loan forgiven without adding any transaction, so no balance changes. The forgiven amount counts in reports as an expense on this date."
        static let debtForgiveFooter: LocalizedStringResource = "Marks the Debt forgiven without adding any transaction, so no balance changes. The forgiven amount counts in reports as income on this date."
        static let loanForgivenFooter: LocalizedStringResource = "The forgiven amount counts in reports as an expense. Un-forgive makes it outstanding again."
        static let debtForgivenFooter: LocalizedStringResource = "The forgiven amount counts in reports as income. Un-forgive makes it outstanding again."
        static let loanReminder: LocalizedStringResource = "Loan reminder"
        static let debtReminder: LocalizedStringResource = "Debt reminder"
        static let outstanding: LocalizedStringResource = "Outstanding"
        static let unforgive: LocalizedStringResource = "Un-forgive"
        static let recordPayment: LocalizedStringResource = "Record Payment"
        static let couldntChange: LocalizedStringResource = "Couldn't Change Loan or Debt"
        static let countsAs: LocalizedStringResource = "Counts As"
        static let cantRecordPayment: LocalizedStringResource = "Can't Record Payment"
        static let onlyLoanOrDebtPaidBack: LocalizedStringResource = "Only a Loan or a Debt can be paid back."
        static let couldntRecordPayment: LocalizedStringResource = "Couldn't Record Payment"
        static let aboveOutstanding: LocalizedStringResource = "Above Outstanding"
        static let reminder: LocalizedStringResource = "Reminder"
        static let remindMeOn: LocalizedStringResource = "Remind Me On"
        static func due(_ day: String) -> LocalizedStringResource { "Due \(day)" }
        static func ofOwed(_ amount: String) -> LocalizedStringResource { "of \(amount)" }
        static func dueReminders(_ count: Int) -> LocalizedStringResource { "\(count) Due Reminders" }
        static func loanOn(_ day: String) -> LocalizedStringResource { "Loan · \(day)" }
        static func debtOn(_ day: String) -> LocalizedStringResource { "Debt · \(day)" }
        static func lent(_ amount: String) -> LocalizedStringResource { "Lent \(amount)" }
        static func collected(_ amount: String) -> LocalizedStringResource { "Collected \(amount)" }
        static func forgivenAmount(_ amount: String) -> LocalizedStringResource { "Forgiven \(amount)" }
        static func borrowed(_ amount: String) -> LocalizedStringResource { "Borrowed \(amount)" }
        static func repaid(_ amount: String) -> LocalizedStringResource { "Repaid \(amount)" }
        static func kept(_ amount: String) -> LocalizedStringResource { "Kept \(amount)" }
        static func owesYou(_ name: String, _ amount: String) -> LocalizedStringResource { "\(name) owes you \(amount)." }
        static func youOwe(_ name: String, _ amount: String) -> LocalizedStringResource { "You owe \(name) \(amount)." }
    }

    /// Recurring transactions and how often they repeat.
    enum Recurring {
        static let alreadyAttached: LocalizedStringResource = "That transaction is in Recently Deleted or already belongs to a Recurring transaction."
        static let missingName: LocalizedStringResource = "Give the recurring transaction a name."
        static let cardNotInWallet: LocalizedStringResource = "Choose a Card paid from this wallet."
        static let untilBeforeStart: LocalizedStringResource = "The last day can't be before the start date."
        static let noOccurrences: LocalizedStringResource = "Repeat at least once."
        static let inactive: LocalizedStringResource = "A paused or deleted recurring transaction can't add a transaction."
        static let incomplete: LocalizedStringResource = "Choose a wallet and a category in Edit first."
        static let amountToConfirm: LocalizedStringResource = "Amount to confirm"
        static let couldntSaveAmount: LocalizedStringResource = "Couldn't Save Amount"
        static let noTransactionsToLink: LocalizedStringResource = "No Transactions to Link"
        static let noTransactionsToLinkDescription: LocalizedStringResource = "Transactions that no Recurring transaction holds appear here."
        static let linkTransaction: LocalizedStringResource = "Link Transaction"
        static let couldntLink: LocalizedStringResource = "Couldn't Link Transaction"
        static let pastOccurrences: LocalizedStringResource = "Past Occurrences"
        static let addAll: LocalizedStringResource = "Add All"
        static let couldntAddTransactions: LocalizedStringResource = "Couldn't Add Transactions"
        static let bill: LocalizedStringResource = "Bill"
        static let subscription: LocalizedStringResource = "Subscription"
        static let purchase: LocalizedStringResource = "Purchase"
        static let regular: LocalizedStringResource = "Regular"
        static let bills: LocalizedStringResource = "Bills"
        static let subscriptions: LocalizedStringResource = "Subscriptions"
        static let purchases: LocalizedStringResource = "Purchases"
        static let deleted: LocalizedStringResource = "Recurring Transaction Deleted"
        static let repeatTitle: LocalizedStringResource = "Repeat"
        static let next: LocalizedStringResource = "Next"
        static let paused: LocalizedStringResource = "Paused"
        static let ended: LocalizedStringResource = "Ended"
        static let progress: LocalizedStringResource = "Progress"
        static let walletArchivedFooter: LocalizedStringResource = "Its wallet is archived, so it makes nothing until the wallet is unarchived."
        static let addTheTransaction: LocalizedStringResource = "Add the Transaction"
        static let addAPayment: LocalizedStringResource = "Add a payment"
        static let linkExisting: LocalizedStringResource = "Link existing"
        static let unlink: LocalizedStringResource = "Unlink"
        static let transactionsFooter: LocalizedStringResource = "The transactions it makes appear here, on their due days."
        static let deleteRecurring: LocalizedStringResource = "Delete Recurring Transaction"
        static let deleteQuestion: LocalizedStringResource = "Delete this recurring transaction?"
        static let couldntChange: LocalizedStringResource = "Couldn't Change Recurring Transaction"
        static let newRecurring: LocalizedStringResource = "New Recurring Transaction"
        static let editRecurring: LocalizedStringResource = "Edit Recurring Transaction"
        static let couldntSave: LocalizedStringResource = "Couldn't Save Recurring Transaction"
        static let starts: LocalizedStringResource = "Starts"
        static let madeEachTimeFooter: LocalizedStringResource = "Each time it falls due, a transaction is made with this name, amount, wallet, category and Card."
        static let amountVaries: LocalizedStringResource = "Amount varies"
        static let estimate: LocalizedStringResource = "Estimate"
        static let estimateFooter: LocalizedStringResource = "Each transaction starts as an estimate, the average of recent transactions in its category, until you enter the real amount. The amount above is used only when the category has no history yet."
        static let noneYet: LocalizedStringResource = "None yet"
        static let totalPrice: LocalizedStringResource = "Total price"
        static let totalPriceFooter: LocalizedStringResource = "Payments attached to it count as paid toward this total. Leave it at zero when there isn't one."
        static let unit: LocalizedStringResource = "Unit"
        static let ends: LocalizedStringResource = "Ends"
        static let lastDay: LocalizedStringResource = "Last day"
        static let once: LocalizedStringResource = "Once"
        static let noRecurring: LocalizedStringResource = "No Recurring Transactions"
        static let noRecurringDescription: LocalizedStringResource = "Bills, subscriptions and income that repeat are added for you on their dates."
        static let addRecurring: LocalizedStringResource = "Add Recurring Transaction"
        static let allWallets: LocalizedStringResource = "All wallets"
        static let noWallet: LocalizedStringResource = "No wallet"
        static let daily: LocalizedStringResource = "Daily"
        static let weekly: LocalizedStringResource = "Weekly"
        static let biWeekly: LocalizedStringResource = "Bi-weekly"
        static let monthly: LocalizedStringResource = "Monthly"
        static let yearly: LocalizedStringResource = "Yearly"
        static let days: LocalizedStringResource = "Days"
        static let weeks: LocalizedStringResource = "Weeks"
        static let months: LocalizedStringResource = "Months"
        static let years: LocalizedStringResource = "Years"
        static let never: LocalizedStringResource = "Never"
        static let onADate: LocalizedStringResource = "On a date"
        static let afterCount: LocalizedStringResource = "After a number of times"
        static let everyDay: LocalizedStringResource = "Every day"
        static let everyWeek: LocalizedStringResource = "Every week"
        static let everyMonth: LocalizedStringResource = "Every month"
        static let everyYear: LocalizedStringResource = "Every year"
        static let onceLowercase: LocalizedStringResource = "once"
        static let onTheLastDay: LocalizedStringResource = "on the last day"
        static func paid(_ amount: String) -> LocalizedStringResource { "\(amount) paid" }
        static func paidOfTotal(_ paid: String, _ total: String) -> LocalizedStringResource { "\(paid) of \(total) paid" }
        static func estimatedAt(_ name: String, _ estimate: String) -> LocalizedStringResource { "\(name) was estimated at \(estimate). Enter the real amount." }
        static func estimatedFromRecent(_ category: String) -> LocalizedStringResource { "\(category) was estimated from recent transactions in its category. Enter the real amount to confirm it." }
        static func deleteMessage(_ days: Int) -> LocalizedStringResource { "It goes to Recently Deleted for \(days) days. The transactions it made or that are attached stay in your wallets." }
        static func remindDaysLater(_ days: Int) -> LocalizedStringResource { "Remind me \(days) days later" }
        static func every(_ count: Int) -> LocalizedStringResource { "Every \(count)" }
        static func times(_ count: Int) -> LocalizedStringResource { "\(count) times" }
        static func noneFromWallet(_ wallet: String) -> LocalizedStringResource { "None are paid from \(wallet)." }
        static func walletPaused(_ wallet: String) -> LocalizedStringResource { "\(wallet) · Paused" }
        static func walletEnded(_ wallet: String) -> LocalizedStringResource { "\(wallet) · Ended" }
        static func walletNext(_ wallet: String, _ day: String) -> LocalizedStringResource { "\(wallet) · Next \(day)" }
        static func everyDays(_ count: Int) -> LocalizedStringResource { "Every \(count) days" }
        static func everyWeeks(_ count: Int) -> LocalizedStringResource { "Every \(count) weeks" }
        static func everyMonths(_ count: Int) -> LocalizedStringResource { "Every \(count) months" }
        static func everyYears(_ count: Int) -> LocalizedStringResource { "Every \(count) years" }
        static func onDate(_ date: String) -> LocalizedStringResource { "on \(date)" }
        static func until(_ date: String) -> LocalizedStringResource { "until \(date)" }
        static func onThe(_ day: String) -> LocalizedStringResource { "on the \(day)" }
        static func onTheFirst(_ weekday: String) -> LocalizedStringResource { "on the first \(weekday)" }
        static func onTheSecond(_ weekday: String) -> LocalizedStringResource { "on the second \(weekday)" }
        static func onTheThird(_ weekday: String) -> LocalizedStringResource { "on the third \(weekday)" }
        static func onTheFourth(_ weekday: String) -> LocalizedStringResource { "on the fourth \(weekday)" }
        static func onTheLast(_ weekday: String) -> LocalizedStringResource { "on the last \(weekday)" }
    }

    /// Money paid back on an expense.
    enum Reimbursements {
        static let notAnExpense: LocalizedStringResource = "Only an Expense can be reimbursed."
        static let notADeposit: LocalizedStringResource = "Only money that came in can be moved into an Expense."
        static let otherWallet: LocalizedStringResource = "Only money that came into the Expense's own wallet can be moved into it."
        static let someonePaidMeBackTitle: LocalizedStringResource = "Someone Paid Me Back"
        static let editReimbursement: LocalizedStringResource = "Edit Reimbursement"
        static let receivedIn: LocalizedStringResource = "Received In"
        static let elsewhereFooter: LocalizedStringResource = "Recorded as money in that wallet, on the day you received it, linked to the expense. The expense shows its net in the Total."
        static let editorFooter: LocalizedStringResource = "Kept on the expense, which then counts what is left of it. No transaction is made."
        static let couldntSave: LocalizedStringResource = "Couldn't Save Reimbursement"
        static let noTransactionsToMoveIn: LocalizedStringResource = "No Transactions to Move In"
        static let noTransactionsToMoveInDescription: LocalizedStringResource = "Money that came into this wallet, such as a deposit, appears here."
        static let moveTransactionIn: LocalizedStringResource = "Move Transaction In"
        static let couldntMoveIn: LocalizedStringResource = "Couldn't Move Transaction In"
        static let someonePaidMeBack: LocalizedStringResource = "Someone paid me back"
        static let moveExistingIn: LocalizedStringResource = "Move an existing transaction in"
        static let sectionFooter: LocalizedStringResource = "Money paid back into this wallet is kept on this expense, and its net, what is left of it, counts in your balance and reports. Money paid back into another wallet is a transaction there."
        static let couldntDelete: LocalizedStringResource = "Couldn't Delete Reimbursement"
    }

    /// The Report screen and its cards.
    enum Report {
        static let everythingElse: LocalizedStringResource = "Everything else"
        static let nothingInCategory: LocalizedStringResource = "Nothing in this category in the period."
        static let whatNetIncomeCounts: LocalizedStringResource = "What Net income counts"
        static let seeDetails: LocalizedStringResource = "See details"
        static let netIncomeExplanation: LocalizedStringResource = "Income less Spent: what came in less what went out, not counting transfers, starting balances, Loan and Debt payments, or anything excluded from report."
        static let cantCountIncome: LocalizedStringResource = "Can't Count Income"
        static let whatTheAverageIs: LocalizedStringResource = "What the Average is"
        static let comparedToLastYear: LocalizedStringResource = "Compared to last year"
        static let comparedTo3WeekAverage: LocalizedStringResource = "Compared to 3-Week Avg"
        static let comparedTo3MonthAverage: LocalizedStringResource = "Compared to 3-Month Avg"
        static let comparedTo3QuarterAverage: LocalizedStringResource = "Compared to 3-Quarter Avg"
        static let comparedTo3YearAverage: LocalizedStringResource = "Compared to 3-Year Avg"
        static let comparedToAverage: LocalizedStringResource = "Compared to Average"
        static let averageExplanation: LocalizedStringResource = "The Average is the mean of the running totals of up to three complete earlier periods of this length, counting from the first period with anything in it."
        static let dailyAverage: LocalizedStringResource = "Daily average"
        static let shows: LocalizedStringResource = "Shows"
        static let breakdown: LocalizedStringResource = "Breakdown"
        static let trend: LocalizedStringResource = "Trend"
    }

    /// Searching and filtering transactions.
    enum Search {
        static let clearFilters: LocalizedStringResource = "Clear Filters"
        static let netTotal: LocalizedStringResource = "Net total"
        static let noMatching: LocalizedStringResource = "No Matching Transactions"
        static let tryChangingFilters: LocalizedStringResource = "Try changing the filters."
        static let cardTotalFooter: LocalizedStringResource = "The list's header shows the Card's total for the period."
        static let dateRange: LocalizedStringResource = "Date Range"
        static let atLeast: LocalizedStringResource = "At least"
        static let atMost: LocalizedStringResource = "At most"
        static let amountRange: LocalizedStringResource = "Amount Range"
        static let amountRangeFooter: LocalizedStringResource = "Amounts as entered, whether money went in or out."
        static let excludedOnly: LocalizedStringResource = "Excluded from report only"
        static let searchTransactions: LocalizedStringResource = "Search Transactions"
        static let searchDescription: LocalizedStringResource = "Find a note, a category or an amount in every wallet, across all time."
        static func cardTotal(_ card: String) -> LocalizedStringResource { "\(card) total" }
    }

    /// Recently Deleted: restoring items or removing them for good.
    enum RecentlyDeleted {
        static let notDeleted: LocalizedStringResource = "It isn't in Recently Deleted."
        static let walletIsDeleted: LocalizedStringResource = "Its wallet is in Recently Deleted. Restore the wallet first."
        static let deletedWithWallet: LocalizedStringResource = "It was deleted with its wallet. Restore or delete the wallet instead."
        static let loanOrDebtIsForgiven: LocalizedStringResource = "Its Loan or Debt was forgiven since. Un-forgive it first."
        static let deleteForever: LocalizedStringResource = "Delete Forever"
        static let nothingRecentlyDeleted: LocalizedStringResource = "Nothing Recently Deleted"
        static let emptyBin: LocalizedStringResource = "Empty Bin"
        static let couldntChange: LocalizedStringResource = "Couldn't Change Recently Deleted"
        static let deleteWalletForever: LocalizedStringResource = "Delete this wallet forever?"
        static let deleteRecurringForever: LocalizedStringResource = "Delete this recurring transaction forever?"
        static let deleteTransactionForever: LocalizedStringResource = "Delete this transaction forever?"
        static let emptyQuestion: LocalizedStringResource = "Empty Recently Deleted?"
        static let walletRemovalMessage: LocalizedStringResource = "The wallet and its transactions and recurring transactions will be removed for good. This can't be undone."
        static let recurringRemovalMessage: LocalizedStringResource = "The recurring transaction will be removed for good. Its transactions stay in your wallets. This can't be undone."
        static let transactionRemovalMessage: LocalizedStringResource = "The transaction will be removed for good. This can't be undone."
        static let everythingRemovalMessage: LocalizedStringResource = "Every wallet, recurring transaction and transaction in Recently Deleted will be removed for good. This can't be undone."
        static let restoreWalletFirst: LocalizedStringResource = "Restore its wallet first"
        static func emptyDescription(_ days: Int) -> LocalizedStringResource { "Deleted wallets, recurring transactions and transactions wait here for \(days) days before they're removed for good." }
        static func footer(_ days: Int) -> LocalizedStringResource { "Items are removed for good after \(days) days. Swipe an item to restore it or delete it forever." }
        static func transactionCount(_ count: Int) -> LocalizedStringResource { "\(count) transactions" }
        static func daysLeft(_ days: Int) -> LocalizedStringResource { "\(days) days left" }
    }

    /// Importing a MoneyLover or Grosh CSV, and exporting one.
    enum ImportExport {
        static let notAMoneyLoverExport: LocalizedStringResource = "This isn't a MoneyLover CSV export. It needs Date, Category, Amount and Wallet columns."
        static let noTransactionsInFile: LocalizedStringResource = "This file has no transactions."
        static let chooseCSVFile: LocalizedStringResource = "Choose CSV File…"
        static let importFooter: LocalizedStringResource = "Replaces every wallet, Card and transaction with those in a MoneyLover CSV export, or restores a Grosh CSV export. Your categories are kept."
        static let replaceAllDataQuestion: LocalizedStringResource = "Replace all data?"
        static let replaceAllData: LocalizedStringResource = "Replace All Data"
        static let importing: LocalizedStringResource = "Importing…"
        static let couldntImport: LocalizedStringResource = "Couldn't Import"
        static let cardsCreated: LocalizedStringResource = "Cards created"
        static let imported: LocalizedStringResource = "Imported"
        static let everythingMatched: LocalizedStringResource = "Every transfer and payment was matched."
        static let unmatchedRows: LocalizedStringResource = "Unmatched rows"
        static let balanceAdjustmentFallback: LocalizedStringResource = "No partner: recorded as a balance adjustment"
        static let notImported: LocalizedStringResource = "No partner and no amount: not imported"
        static let unlinkedPayment: LocalizedStringResource = "No open Loan or Debt of this amount: not linked"
        static let shareCSV: LocalizedStringResource = "Share CSV File…"
        static let exportFooter: LocalizedStringResource = "Every transaction in MoneyLover's CSV format, with its Card and the transactions it is linked to. Import from MoneyLover restores it with “Replace all data”."
        static let couldntExport: LocalizedStringResource = "Couldn't Export"
        static func invalidLine(_ line: Int) -> LocalizedStringResource { "Line \(line) of the file has no valid date, amount, category or wallet." }
        static func replaceConfirmation(_ count: Int, _ fileName: String) -> LocalizedStringResource { "Every wallet, Card and transaction will be deleted and replaced with the \(count) transactions in \(fileName). Categories are kept. This can't be undone." }
        static func unmatchedRow(_ line: Int, _ day: String, _ wallet: String) -> LocalizedStringResource { "Line \(line) · \(day) · \(wallet)" }
    }

    /// The amount keypad's keys, as shown and as VoiceOver reads them.
    enum Keypad {
        static let allClearKey: LocalizedStringResource = "AC"
        static let doubleZero: LocalizedStringResource = "Double zero"
        static let allClear: LocalizedStringResource = "All clear"
        static let plus: LocalizedStringResource = "Plus"
        static let minus: LocalizedStringResource = "Minus"
        static let times: LocalizedStringResource = "Times"
        static let dividedBy: LocalizedStringResource = "Divided by"
        static let equals: LocalizedStringResource = "Equals"
        static let changeSign: LocalizedStringResource = "Change Sign"
    }

    /// Settings and the screens not built yet.
    enum Settings {
        static let sounds: LocalizedStringResource = "Sounds"
        static let haptics: LocalizedStringResource = "Haptics"
        static let chime: LocalizedStringResource = "Chime"
        static let soundsAndHaptics: LocalizedStringResource = "Sounds & Haptics"
        static let marimba: LocalizedStringResource = "Marimba"
        static let glassBells: LocalizedStringResource = "Glass bells"
        static let bubblePops: LocalizedStringResource = "Bubble pops"
        static let topSpending: LocalizedStringResource = "Top spending"
        static let budgetsMessage: LocalizedStringResource = "Set a spending limit for a category and see how much is left each month."
        static let topSpendingMessage: LocalizedStringResource = "Your biggest spending categories this month will appear here."
    }

    /// Choosing and cropping a Card's image or a category's icon.
    enum Photos {
        static let zoom: LocalizedStringResource = "Zoom"
        static let cropHint: LocalizedStringResource = "Drag to move the photo. Pinch, or use the slider, to zoom."
        static let couldntSave: LocalizedStringResource = "Couldn't Save Photo"
        static let couldntCrop: LocalizedStringResource = "The photo couldn't be cropped."
        static let image: LocalizedStringResource = "Image"
        static let cropIcon: LocalizedStringResource = "Crop Icon"
        static let cropImage: LocalizedStringResource = "Crop Image"
        static let replace: LocalizedStringResource = "Replace"
        static let choosePhoto: LocalizedStringResource = "Choose Photo"
        static let couldntUse: LocalizedStringResource = "Couldn't Use Photo"
        static let unreadable: LocalizedStringResource = "That photo can't be read."
    }
}
