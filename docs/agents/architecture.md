# Architecture and performance

How Grosh is put together, and the performance rules every change has to keep. Domain words (Split, Reimbursement, Recently Deleted, Card statement…) mean what `GLOSSARY.md` says; the decisions behind them are in `docs/adr/`.

## The 16k store

Design every change for **the 16k store**: about 16,000 transactions over six years, the size a long-time user or a Money Lover import reaches. Anything that touches each transaction once per frame, per row or per save is visible there, even when it is invisible in a fresh simulator. `Grosh/Debug/BenchmarkStore.swift` builds this store, and `GroshTests/PerformanceBenchmarks.swift` times launch, every screen, scrolling, search and saving on it. The UI smoke walk opens the app on it too (`docs/agents/ui-smoke.md`).

## Components

| Folder | Holds | Rule |
| --- | --- | --- |
| `Grosh/Model/` | SwiftData `@Model` classes, the values their stored fields hold (`CategoryType`, `LinkKind`, `RecurringKind`, `RepeatUnit`…), `Money`, `CalendarDay`, and `GroshStore` (the schema and the container). | Depends on nothing else in the app. Every property optional or defaulted, no `.unique`, every relationship optional with an inverse (ADR-0001). A new model goes into `GroshStore.schema`. |
| `Grosh/Domain/<Concept>/` | The rules: extensions on the models, value types (drafts, summaries, `LedgerEntry`), and `FetchDescriptor`s named for what they read (`MonthGraphHistory.transactions(for:)`, `RecentlyDeleted.deletedTransactions`). `Domain/Store/StoreOpening` opens the store and brings it up to date (seeding, migrations) before any screen reads it. | Plain Swift plus SwiftData: no SwiftUI, and nothing from `Features/` or `Views/`. Value types stay free of `ModelContext`; whatever a calculation needs from the store is fetched by its caller and passed in. |
| `Grosh/Features/<Area>/` | SwiftUI screens and rows, one folder per area of the app, and their view state (`TransactionGrouping`). | Views read data and call Domain rules. Arithmetic, eligibility and sign handling live in Domain, where tests reach them. |
| `Grosh/Strings.swift` | `Strings`, every piece of text the app shows (its English is the String Catalog key). | Domain and Features use it; it depends on nothing. |
| `Grosh/GroshApp.swift`, `Grosh/RootView.swift` | The app's entry point and its tabs. | The one place that puts the Features' screens together. |
| `Grosh/Views/` | SwiftUI pieces every area shares: `@NotDeletedTransactions`, `@SavedWalletBalances`, `Today`, colors, pickers, the photo cropper. | Like `Features/`, no rules of their own. |
| `Grosh/Logging/` | `Log`, one `os.Logger` per area, and `Signpost`, the intervals Instruments shows. | A message names what failed and the error, never the data (`docs/agents/logging.md`). |
| `Grosh/Debug/` | The 16k store generator and the UI test launch hook. | Wrapped in `#if DEBUG`, so the shipped app never carries them. |
| `GroshTests/` | Swift Testing suites, one per behaviour, each with its own in-memory container (`TestStore.makeContainer()`, which counts and checks its saved month totals as below), plus shared fixtures: `TestStore.swift` (the seeded store, its day, and the helpers that make wallets, transactions, Loans, payments and paybacks the way the app does) and the `*Fixture.swift` built on it. | A Domain rule ships with tests written first. |

The app, the UI test store and every preview open the store through `StoreOpening.open` (or `StoreOpening.prepare` on a container opened elsewhere), so each starts from the same seeded, migrated store. From then on, each save of its main context counts again the saved month totals it made dirty, as the save begins, so they go into that same save (`WalletMonthTotals`, ADR-0013); every store a test makes does the same (`TestStore.checked`), and its totals are checked against a full count when the test ends. Startup work runs in `GroshApp` on `scenePhase == .active`: `RecentlyDeleted.purgeExpired` and `RecurringTransaction.catchUp`. Both are on the launch benchmark.

## Where a screen gets its transactions

Pick the narrowest source that answers the question:

1. **Every transaction outside Recently Deleted**: `@NotDeletedTransactions`. It reads the store once per model context and keeps itself in step with each save from the identifiers the save reports, so N open screens cost one read, not N per save. Its projected value (`$transactions`) is the `[LedgerEntry]` list for balances.
2. **A slice of them**: `@Query` with a predicate that narrows in the store: a link (`RelatedTransactionsSection`), a date range (`MonthGraphHistory`), a category, Recently Deleted. Put the `FetchDescriptor` in Domain under a name that says what it reads.
3. **One answer from the whole store** (the earliest counted day, whether anything matches): a `FetchDescriptor` with a sort and `fetchLimit`, rather than loading everything and reducing in Swift.

`@Query(Transaction.notDeleted)` re-reads all ~16k rows after every save, once per screen showing it, so no screen uses it.

Wallet balances on Home, the Wallets list and the Wallet selector (Transactions tab and Report) come from the saved month totals, not the transactions: `@SavedWalletBalances` reads `WalletBalances.read(asOf:in:)` (each wallet's totals through this month, less this month's transactions dated after today, ADR-0013) once per save of the view's context and again when the day changes. Home has no `@NotDeletedTransactions` at all, so it draws without reading every transaction. The editors that show balances (Transfer, Adjust Balance) still add them up from `@NotDeletedTransactions`.

What counts on the Month graph and in the Report comes from one place, `CountedHistory`: each Report screen builds it once per draw from `@NotDeletedTransactions` (`CountedHistoryReader`), and Home's Month graph from the few months `MonthGraphHistory` reads (`MonthGraphHistory.read` does the same for tests and the benchmark). Its strip, first counted day, period totals and lists are the ones every screen shows.

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
- **A rule saves through the store, or refuses.** A rule that changes a model and saves reaches the store with `storeContext()` or `saveToStore()` (`Domain/Store/StoreContext.swift`), never `modelContext?.save()`: a model the store no longer holds throws `StoreError.notInStore` instead of dropping the change without a word.
- **One home per rule.** A check like "is this an ordinary Expense" or "which part is the original" lives in one Domain property that every caller uses; a second copy in a view, export or report drifts from the first.
