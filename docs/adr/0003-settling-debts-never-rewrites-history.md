> Superseded in part by [ADR 0008](0008-reimbursements-are-stored-on-the-expense.md): a Reimbursement lands in the wallet on the Expense's own day, so the original is no longer the amount every balance uses.
>
> Superseded in part by [ADR 0004](0004-forgiving-marks-the-original-instead-of-adding-transactions.md): forgiving no longer adds transactions.

# Settling a Debt or Loan never rewrites the original transaction

When a Loan is paid back (or a Debt repaid), the original transaction keeps its amount and date. The repayment is recorded as new transaction(s) on the repayment date, linked to the original: the owed portion under Debt Collection or Repayment (excluded from report), and anything above it as ordinary income or expense. We considered zeroing the original and adding only the difference, which gives the same report numbers, but it moves every opening and ending balance between the two dates and breaks reconciliation against bank statements, which is the main reason the user keeps these records.
