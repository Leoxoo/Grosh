# Logging and signposts

What Grosh says while it runs: `os.Logger` messages to read in Console.app or from the simulator's log, and a signpost interval for Instruments. Both live in `Grosh/Logging/Log.swift`.

## Loggers

One subsystem, `Leoxo.Grosh` (the bundle identifier), and a category per area:

| Category | Logger | Covers |
| --- | --- | --- |
| `Store` | `Log.store` | Saves, fetches and the clean-up at startup. |
| `Import` | `Log.importing` | Import from MoneyLover. |
| `Recurring` | `Log.recurring` | Recurring transactions making what came due. |
| `Reminders` | `Log.reminders` | Scheduling Loan, Debt and Estimated-amount reminders. |
| `Reports` | `Log.reports` | The Report. Nothing logs here yet. |

In a `catch`, `Log.store.failed("Saving a transaction", error)`. Where a `try?` dropped the error, `Log.store.attempt("Reading every transaction") { try … } ?? []` gives the same value and logs why it failed. Log only on save, fetch, import and reminder paths, never in a row, a per-transaction loop or anything that runs per frame.

**Levels.** `error` is the store or the system failing, which should never happen, and `tools/check` fails a test run that logs one (`docs/agents/log-check.md`). `info` is a failure the tests exercise on purpose: one of Grosh's own rules refusing a change (an invalid draft, a locked or missing category, a bad import file), or a file the person picked that can't be read. `failed` chooses by the error's type, so a call site does not. `fault` is not used.

**Privacy.** A message names what failed and the kind of error: Grosh's error case, or a system error's domain and code. Never an amount, note, payee, name, account detail or file name, and never an error's message or user info, which can quote the record that failed.

## Reading the log

From a booted simulator, errors and faults:

```
xcrun simctl spawn booted log show --last 10m --style compact \
    --predicate 'subsystem == "Leoxo.Grosh" AND (messageType == error OR messageType == fault)'
```

Add `--info` and drop the `messageType` part to see the `info` messages too, or `AND category == "Import"` to narrow to an area. Write `messageType == error` without quotes.

From a device, in Console.app: select the device in the sidebar, click Start, filter by Subsystem `Leoxo.Grosh` (type it in the search field and pick Subsystem), and turn on Action ▸ Include Info Messages.

## Signposts

`Signpost.performance` is the `Performance` category of the same subsystem. It has one interval, `Launch`: the work the app does when it becomes active, which is its startup work at launch (`RecentlyDeleted.purgeExpired` and `RecurringTransaction.catchUp`). It runs again each time the app returns to the foreground.

To see it, choose Product ▸ Profile (⌘I) in Xcode, pick the Time Profiler template, click + and add the os_signpost instrument (Signposts in newer Xcode versions), then record and use the app. Filter the signpost track to subsystem `Leoxo.Grosh`. Select a `Launch` bar and the Time Profiler's call tree covers only that interval.

A UI test measures it with `XCTOSSignpostMetric(subsystem: "Leoxo.Grosh", category: "Performance", name: "Launch")` in `measure(metrics:)`.

To add an interval, put a `begin<Name>()` beside `beginLaunch()` in `Log.swift` with its own name literal, and call it with `defer { interval.end() }` on the next line, so every way out closes it.

## Written without a Mac

Nothing here has been compiled or run, so the first build and run settle these:

- The `os` calls follow Apple's documented signatures (`Logger(subsystem:category:)`, `info`, `error`, `OSSignposter.beginInterval` and `endInterval`). A call the compiler rejects is in `Log.swift`.
- That `log show` prints the `info` messages with `--info` after the fact: the system may keep `info` only in memory.
- The Instruments and Console menu names above, which move between Xcode versions.
