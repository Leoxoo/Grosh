# Running the tests

Agents run **`tools/check`**, never `xcodebuild test` directly. It builds Grosh, runs the tests on an iPhone simulator and prints only what failed, so a run costs a few lines instead of hundreds of kilobytes of log. It also skips the 600 s wait for simulator diagnostics that a failing `xcodebuild test` adds, and it takes turns with other runs on the same Mac.

```
tools/check                                  # the unit tests (GroshTests)
tools/check --ui                             # the unit tests and the UI tests (GroshUITests)
tools/check --only ReimbursementTests        # one suite
tools/check --only 'ReimbursementTests/deletingAReimbursementDoesNotDeleteItsExpense()'   # one test
```

- Run it from anywhere in the repository. It needs Xcode, so it only runs on a Mac.
- `--only` takes a suite's type name, or a test's function name with its parentheses and argument labels (`AmountEntryTests/parsesTypedAmounts(_:)`). Repeat it to run several. It looks in GroshTests, and in GroshUITests too when `--ui` is given. A name that starts with `GroshTests/` or `GroshUITests/` is used as it is.
- The benchmarks stay skipped: tools/check never sets `GROSH_BENCHMARK`. To time a change, use the benchmark command in [architecture.md](architecture.md#performance-rules). It is the one place for raw `xcodebuild`, as it needs an optimized build.

## What it prints

A passing run prints three lines:

```
Simulator: iPhone 17 Pro (iOS 26.4)
412 passed in 48s (9 skipped)
Result: /var/folders/…/T/grosh-check.Ab12Cd/Grosh.xcresult
```

A failing run prints one line per failure, then the summary and where the full results are:

```
Simulator: iPhone 17 Pro (iOS 26.4)
FAIL ReimbursementTests/deletingAReimbursementDoesNotDeleteItsExpense(): GroshTests/ReimbursementTests.swift:42: Expectation failed: (net → -1500) == 0
410 passed, 2 failed in 48s (9 skipped)
Full log: /var/folders/…/T/grosh-check.Ab12Cd/xcodebuild.log
Result: /var/folders/…/T/grosh-check.Ab12Cd/Grosh.xcresult
```

- `FAIL <Suite>/<test>: <file>:<line>: <message>` for each failed expectation, up to five per test. A parameterized test names the failing arguments in brackets after the test.
- `ERROR <file>:<line>: <message>` for each build error. The summary then reads `0 passed, 0 failed in 23s (the build failed)`.
- Errors that Grosh logged during the run, from `tools/check-logs`, come just before the summary, each led by the test that was running (`docs/agents/log-check.md`). A new suite gets `@Suite(.namedInTheLog)`, as every suite has, or its messages carry only their time. The summary then ends in `; Grosh logged errors (tools/check-logs)`. `tools/check-logs` reads the simulator the tests ran on. tools/check boots that simulator when it is down, and shuts it down once the log is read. If it is still not booted, the check is skipped, the output says so, and the outcome is not changed.
- When a test crashed, or a UI test failed, the output adds why, after the failures: the runtime's `Fatal error:` lines from the log, then the crashed thread's top frames from the newest crash report of Grosh that macOS wrote during the run (in `~/Library/Logs/DiagnosticReports`; `GROSH_CRASH_REPORTS` names another folder). It waits up to ten seconds for that report, and says so when none was written.
- Any other line says why the outcome could not be read: no simulator, xcodebuild stopping before it wrote a result bundle, JSON of an unexpected shape, or `GroshUITests did not run`. The full log has the details.

The outcome comes from the result bundle, through `xcrun xcresulttool`, not from the log text. Nothing else from xcodebuild is printed. The folder on the last lines keeps the full log, the `.xcresult` bundle (open it in Xcode for attachments and screenshots), and the JSON that xcresulttool printed (`xcresult-*.json`).

## Exit status

| Status | Meaning |
| --- | --- |
| 0 | Every test passed. |
| 1 | A test failed, no test ran (check the `--only` names), `--ui` did not run the UI tests, or Grosh logged errors. |
| 2 | The build failed, or the tests could not run: no simulator, xcodebuild stopped early, or the result bundle could not be read. |
| 3 | xcodebuild is not installed (no Xcode, as in a Linux container), so nothing ran. |
| 64 | The arguments are wrong. |

## Where the results go

Each run makes a new temporary folder, `$TMPDIR/grosh-check.XXXXXX`. When `GROSH_CHECK_RESULT_DIR` is set, the results go to that folder instead, which may already exist. CI makes it, and uploads it when a check fails. A run replaces the `Grosh.xcresult` and `xcodebuild.log` that an earlier run left there.

## Simulator

tools/check uses an available iPhone 17 Pro, otherwise the first available iPhone, on the newest iOS that is at least the app's deployment target. The first line it prints names the simulator. A simulator that is down is booted for the run and shut down again after it; one that was booted stays booted.

## One run at a time

Each xcodebuild boots simulators of its own, so runs from several worktrees at once slow each other down. tools/check first takes a lock: the folder `$TMPDIR/grosh-tools-check.lock`, holding the owner's pid and repository folder, removed when the run ends, Ctrl-C included. A run that finds the lock taken waits for it, and prints `Waiting for another tools/check run (pid N, <folder>)` at once and every 30 seconds.

- The wait counts against your command's timeout. Allow for another session's run ahead of yours: give the command 10 minutes, or run it in the background.
- A lock whose pid has gone, as when a run was killed, is taken over. If a lock stays and its pid is not a tools/check run, remove the folder by hand.
- Runs share the lock only when they share `TMPDIR`.

## Scheme and test plan

The shared `Grosh` scheme tests with `Grosh.xctestplan`. Its one configuration, Default, is the plain run, with no extra arguments or environment. Both test targets are on in the plan. `tools/check` narrows each run with `-only-testing`: a plain run passes `-only-testing:GroshTests`, and `--ui` adds `-only-testing:GroshUITests`. So ⌘U in Xcode runs the UI tests as well as the unit tests. Both test targets run on the chosen simulator itself, not on clones of it (GroshTests is not parallelizable either), so `tools/check-logs` can read what they logged.

If a run with `--ui` prints `GroshUITests did not run`, check that GroshUITests is still on in `Grosh.xctestplan`. Xcode may skip a target the plan turns off, even when `-only-testing` names it.

## Snapshot tests

`GroshTests/SnapshotTests.swift` draws each transaction row kind (Expense, Income, Transfer, Split, Reimbursement) and Home with its Month graph, in light, dark and the accessibility text size AX3, and compares each with a PNG in `GroshTests/__Snapshots__/SnapshotTests/`. It uses [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing), linked to GroshTests only and pinned to 1.19.7 by `Grosh.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. A new version can draw differently, so updating it means recording the references again. Each screen is drawn as of 12 October 2026, from fixed transactions, on a 402 × 874 screen in English (United States), so the same tree draws the same image on any day.

**References recorded on:** a Mac16,7 (Apple M4 Pro) on macOS 27.2 with Xcode 27.1 (27A9275), on the iPhone 17 Pro simulator with iOS 27.0 (24A434). Record and compare on that setup only. The simulator's language and region must be English (United States) too, since amounts and dates use the device's locale.

CI skips the suite and prints one line saying so, because the references belong to a Mac.

```
tools/check --only SnapshotTests
```

- **Record a reference on purpose.** Delete the PNG to replace, or the whole `__Snapshots__/SnapshotTests` folder for all of them, then run. swift-snapshot-testing writes a missing reference and fails its test once, so run again to compare. Or turn on the library's record mode for one run, with the `record` argument of `assertSnapshot` (the pinned version's README describes it). That overwrites every reference the run draws. Take it out again before committing.
- **Review the diff.** A changed screen fails its test, and `tools/check` prints the failure. Open the `Grosh.xcresult` it names in Xcode, and compare the reference with the new image in the failed test's attachments. In git, `git status` lists the changed PNGs: open the old and new files side by side, and commit only the changes you meant to make.

## Testing the tools

These need no Xcode, and CI runs all three on every pull request that changes `tools/`, `.claude/hooks/` or `.github/` (the Tools check). A pull request that changes only docs, Markdown, agent settings or the tools' own tests skips the unit and UI tests; a push to main runs everything (`.github/workflows/tests.yml`):

```
tools/tests/check/run.sh                     # tools/check, against stand-ins for xcodebuild, xcrun and tools/check-logs
tools/tests/run-checks/run.sh                # the Stop hook, .claude/hooks/run-checks.sh
python3 -B -m unittest discover -s tools     # tools/check-logs
```

`tools/tests/run-checks/run.sh` runs the hook on a throwaway repository whose `tools/check` fails while a Swift file holds `BROKEN`, with stand-ins for xcodebuild, curl (LM Studio) and claude (the local model). It covers when the hook runs the tests and what it hands back, the three-failure limit, and the local fix: that a failed attempt leaves the worktree, the index and the stash list as they were. A change to the hook comes with a case there.
