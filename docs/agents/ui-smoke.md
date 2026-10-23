# UI smoke walk

`GroshUITests/GroshUITests.swift` (`testWalkEveryScreen`) drives the real app on the 16k store. It launches Grosh, visits every tab and the main screens a user reaches from them, adds an Expense and looks for it on Home. It fails on a crash or a screen that doesn't appear, and the failure names the step and the screen. It checks that screens appear, not how fast: the benchmarks (`GroshTests/PerformanceBenchmarks.swift`) time screens far more steadily than a UI test can. It does measure launch, with `XCTApplicationLaunchMetric`.

## Running it

`tools/check --ui` runs it after the unit tests, then runs `tools/check-logs --ui`, which names the step each logged error happened in (`docs/agents/log-check.md`). On its own:

```
xcodebuild test -scheme Grosh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -parallel-testing-enabled NO -only-testing:GroshUITests/GroshUITests/testWalkEveryScreen
```

Or click the diamond beside `testWalkEveryScreen` in Xcode. Run it on an iPhone simulator: on iPad the tabs are a sidebar, and the walk looks for a tab bar.

The app makes the store in its launch, before it has a screen, and no screen can be queried until it has one. So the `Launch` step first launches the app with `-GroshUITestStore make`, which makes the store if today's isn't there yet and then quits, and launches it again to open the store. Making the store takes minutes, which is why that quit gets 900 seconds. A CI runner starts from a new simulator, so it makes the store on every run.

## The launch argument

`-GroshUITestStore benchmark` makes the app open the 16k store in place of the user's. Only Debug builds read it (`Grosh/Debug/UITestStore.swift`). `BenchmarkStore` (`Grosh/Debug/BenchmarkStore.swift`), which makes the store for this and for the benchmarks, is compiled into Debug builds only, so the app as shipped carries neither. The benchmarks reach it with `@testable import Grosh`, which works because their build is a Debug build with `-O`.

- The store is `GroshUITest-<yyyymmdd>.store` in the app's temporary directory. It is a file of its own, so the user's store is never opened, and the Expenses the walk adds never reach the benchmarks' copy (`GroshBenchmark-v1.store`). Its history runs up to today, so the first launch of a day makes a new store (with `make`, below) and removes the earlier days' stores.
- Animations are off (`UIView.setAnimationsEnabled(false)`), so the walk never waits on a transition.
- `make` makes the store, if today's isn't there, and quits the app before it shows a screen, so the walk can wait for the quit. Any other value than `benchmark` or `make` stops the app at launch ("No UI test store is called …") rather than opening the user's store.

To look around the 16k store by hand, add `-GroshUITestStore benchmark` under Product → Scheme → Edit Scheme → Run → Arguments, or run `xcrun simctl launch booted Leoxo.Grosh -GroshUITestStore benchmark`.

## Steps

Each step is an activity in the test report. Every screen gets 10 seconds to appear, which only runs out on a hang. The exception is `Launch`: the store gets 900 seconds to be made, and Home 300 seconds to appear.

| Step | What it does |
| --- | --- |
| `Launch` | Launches Grosh with `make`, which makes the 16k store and quits, then launches it on the store and waits for Home. Answers the notifications prompt with Don't Allow: the store has Loan reminders still to come, so a new simulator asks. |
| `Launch → measure` | Launches it five more times under `XCTApplicationLaunchMetric`, then waits for Home. |
| `Home → open` | Home's Total and wallets. |
| `Transactions → open` | The Transactions tab and its list. |
| `Transactions → scroll` | Three swipes down the list. |
| `Transactions → open a transaction` | Taps a row between the list's header and the tab bar, and waits for the Transaction screen. |
| `Transactions → back` | Back to the list. |
| `Search → find a payee` | Searches the Transactions tab for "Sam" and waits for a "Dinner with Sam". The keyboard's Search key then puts the keyboard away, if the field still has focus. |
| `Budgets → open` | The Budgets tab. |
| `Account → open` | The Account tab. |
| `Wallets → open` | Account → Wallets. |
| `Wallets → open a wallet` | Opens Checking's editor and cancels it. |
| `Recurring → open` | Account → Recurring transactions. |
| `Debts & Loans → open` | Account → Debts & Loans. |
| `Recently Deleted → open` | Account → Recently Deleted. |
| `Home → add an Expense` | The + on Home: Expense, 0.42 on the keypad, the category Products (found with the category search), the Card Debit when the suggested wallet needs a Card, a note holding the time, then Save. |
| `Home → see the new Expense` | Scrolls Home to Recent transactions and waits for the row with that note. |

The walk logs each step with `os.Logger`, subsystem `Leoxo.GroshUITests`, category `Steps`: `begin <step>` when it starts and `end <step>` when it ends, at the default level (`notice`), with the step name logged `privacy: .public`. `tools/check-logs` parses exactly these two messages, so keep the wording. It tags logged errors with the step names, so keep them short and stable. A new step is named `<Screen> → <action>`.

The walk finds screens by their navigation bar titles and tabs by their names. Three rows of the Add Transaction form carry accessibility identifiers for it, because their labels change with what is chosen: `TransactionEditor.category`, `TransactionEditor.card` and `TransactionEditor.note`.

## Reading a failure

- `<step>: <screen> did not appear within 10 seconds.` The screen hung, or the title or label the walk looks for changed. The step in `GroshUITests.swift` shows what it looks for.
- `<step>: Grosh is no longer running …` The app crashed, or an uncaught exception ended it. The simulator's crash report is on the Mac in `~/Library/Logs/DiagnosticReports`.
- `Launch: the 16k store was still being made after 900 seconds.` Making the store took longer than that, or the app hung in its launch.
- `Launch: Home did not appear within 300 seconds.` The store opened, but Home did not show: the launch hung, or the screen changed.
- `Failed to get matching snapshots: … kAXErrorServerNotFound`, at any step. XCTest found no running app to query: it had crashed or quit, or it was still in its launch. `tools/check` prints the crash report of a failed UI test. With none written, the app quit or hung without crashing.

## Written without a Mac

This was written where there is no Xcode and no simulator, so none of it has compiled or run. The first run on a Mac settles the points below. Delete this section once it has.

- **It compiles, and the walk passes.**
- **The launch baseline.** It has to be recorded on a Mac and checked in. Run the walk in Xcode. In the test report, open the launch metric's result, click Set Baseline, and commit `Grosh.xcodeproj/xcshareddata/xcbaselines/`. A baseline belongs to the Mac and the simulator it was recorded on, so other machines, CI among them, have nothing to compare against. Until a baseline is recorded, launch is measured and reported but never fails the test.
- **How long it takes.** Once the day's store is made, it should finish in a few minutes on a laptop.
- **Making the store.** The `make` launch quits once the store is made, and a launch that finds the store made already quits after three seconds, so that XCTest sees it running. Check both on a laptop and on CI, and that 900 seconds is enough for a Debug build. If it isn't, raise the `Launch` step's first timeout.
- **What the walk looks for.** Each of these comes from reading the views, not from the accessibility tree:
  - navigation bars named by their screen's title, and tab bar buttons by the tab's name;
  - the back button first in its navigation bar;
  - a row's label joining its texts, so a row holds "Dinner with Sam", and a wallet's row starts with its name;
  - the form's Category and Card rows as buttons that carry their identifiers;
  - the Card menu's choices as buttons named for the Cards;
  - the keypad's keys labelled 4 and 2;
  - the category list's search field;
  - "Don’t Allow" on the notifications prompt;
  - the keyboard's Search key putting the keyboard away.
- **Animations off.** Check that turning them off in `GroshApp.init` takes effect.
- **The step log.** Check that it reaches the simulator's log and that `tools/check-logs --ui` tags messages with it. `docs/agents/log-check.md` has a probe for this.
