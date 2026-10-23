# Architecture and performance

How Grosh is put together, and the performance rules every change has to keep. Domain words (Split, Reimbursement, Recently Deleted, Card statement…) mean what `GLOSSARY.md` says; the decisions behind them are in `docs/adr/`.

## The 16k store

Design every change for **the 16k store**: about 16,000 transactions over six years, the size a long-time user or a Money Lover import reaches. Anything that touches each transaction once per frame, per row or per save is visible there, even when it is invisible in a fresh simulator. `GroshTests/PerformanceBenchmarks.swift` builds this store and times launch, every screen, scrolling, search and saving.

## Components

| Folder | Holds | Rule |
| --- | --- | --- |
| `Grosh/Model/` | SwiftData `@Model` classes, `Money`, `CalendarDay`, `GroshStore` (the container), `NotDeletedTransactions`. | Every property optional or defaulted, no `.unique`, every relationship optional with an inverse (ADR-0001). A new model goes into `GroshStore.schema`. |
| `Grosh/Domain/<Concept>/` | The rules: extensions on the models, value types (drafts, summaries, `LedgerEntry`), and `FetchDescriptor`s named for what they read (`MonthGraphHistory.transactions(for:)`, `RecentlyDeleted.deletedTransactions`). | Plain Swift plus SwiftData: no SwiftUI. Value types stay free of `ModelContext`; whatever a calculation needs from the store is fetched by its caller and passed in. |
| `Grosh/Features/<Area>/` | SwiftUI screens and rows, one folder per area of the app. | Views read data and call Domain rules. Arithmetic, eligibility and sign handling live in Domain, where tests reach them. |
| `GroshTests/` | Swift Testing suites, one per behaviour, each with its own in-memory container (`GroshStore.makeContainer(inMemory: true)`), plus shared fixtures (`*Fixture.swift`). | A Domain rule ships with tests written first. |

Startup work runs in `GroshApp` on `scenePhase == .active`: `RecentlyDeleted.purgeExpired` and `RecurringTransaction.catchUp`. Both are on the launch benchmark.

## Where a screen gets its transactions

Pick the narrowest source that answers the question:

1. **Every transaction outside Recently Deleted**: `@NotDeletedTransactions`. It reads the store once per model context and keeps itself in step with each save from the identifiers the save reports, so N open screens cost one read, not N per save. Its projected value (`$transactions`) is the `[LedgerEntry]` list for balances.
2. **A slice of them**: `@Query` with a predicate that narrows in the store: a link (`RelatedTransactionsSection`), a date range (`MonthGraphHistory`), a category, Recently Deleted. Put the `FetchDescriptor` in Domain under a name that says what it reads.
3. **One answer from the whole store** (the earliest counted day, whether anything matches): a `FetchDescriptor` with a sort and `fetchLimit`, rather than loading everything and reducing in Swift.

`@Query(Transaction.notDeleted)` re-reads all ~16k rows after every save, once per screen showing it. The Report screens still do this; moving them onto `@NotDeletedTransactions` is the known next step.

## What day it is

Screens read the day from `@Environment(\.today)`, a `CalendarDay`. The app sets it once at the root, from the real date, and moves it on when the day changes while the app is open (`Grosh/Views/Today.swift`). A test or a preview shows a screen as of a fixed day with `.environment(\.today, day)`. Views pass it into the Domain rules, which keep taking `today:` as an argument, so a view should not read `CalendarDay.today` or the clock to decide what day it is.

## Performance rules

**Balances and sums read `LedgerEntry`.** A `LedgerEntry` copies a transaction's wallet, day and amount once and is refreshed only when a save changes them. Balance-style code takes `some Sequence<some DatedAmount>` and works on either. Reading a model's properties while a screen draws is the slow path; 16k of them is a quarter of a second.

**One pass, keyed by identity.** Totals over many wallets or categories are one loop into a `[ObjectIdentifier: Int]` (see `WalletBalances`), never a filter per wallet. Sort keys are read once before sorting (`TransactionOrder`).

**Computed properties on a model stay in memory.** A model's computed property is read per row, per balance and per report pass, so it may only read the model's own stored values. Two things turn it into a per-row store hit:

- *Walking a relationship* (`reimbursements`, `wallet.transactions`) faults that relationship for every transaction it is read on. When a balance or list needs a figure from a relationship, store it on the model as a denormalised value updated wherever the relationship changes, or prefetch the relationship (`relationshipKeyPathsForPrefetching`) on the fetch that feeds the list.
- *Running a fetch* (`modelContext.fetch`) inside a property, a `body`, a row, or a loop over transactions. Fetch once at the screen or rule's entry point and pass the result down, or answer from a list the screen already holds (`@NotDeletedTransactions`, the screen's own `@Query`).

**Work once per screen, once per decode.** Images (Card photos, Subscription icons) are decoded once and cached, not per row. Text a search compares against is trimmed and parsed once per search.

**Measure what you touch.** A change to any of the above, or to launch, Home, Transactions, Report, search or saving, gets benchmarked before and after on an optimized build:

```
TEST_RUNNER_GROSH_BENCHMARK=1 xcodebuild test -scheme Grosh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    SWIFT_OPTIMIZATION_LEVEL=-O -parallel-testing-enabled NO -only-testing:GroshTests/PerformanceBenchmarks
```

Put the before → after milliseconds in the commit message, as cc60ff5 and d91cfa8 do.

Each step has a budget in `GroshTests/BenchmarkBudgets.swift`, and a step over its budget fails the run on the setup the budgets were recorded on. To read a budget failure, or to record or change one, see `docs/agents/benchmarks.md`.

## House style

- **Doc comments** say in the user's words what something is or does, using glossary terms, and cite the ADR that decides it (`(ADR-0004)`). They explain *why* a choice was made when the code can't.
- **Commit subjects** describe the user-visible change in plain English ("Keep every transaction in memory instead of re-reading the store after each save"), not the code edit.
- **One home per rule.** A check like "is this an ordinary Expense" or "which part is the original" lives in one Domain property that every caller uses; a second copy in a view, export or report drifts from the first.
