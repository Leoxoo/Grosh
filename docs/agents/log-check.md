# Log check

`tools/check-logs` fails a test run when the app logged an error, a fault or a runtime issue. Xcode's console shows these as yellow (`error`) and red (`fault`) lines and, in the Issue navigator, as purple runtime issues such as SwiftUI's "Publishing changes from within view updates is not allowed". Most come from SwiftUI, SwiftData or UIKit, not from Grosh's own code, so they carry no file and line in Grosh. The useful location is the screen or step the app was on. Left alone they scroll past in the console and stay.

`tools/check` runs it after the tests (with `--ui` when the UI tests ran) and fails the run when it exits non-zero. By hand:

```
tools/check-logs --since EPOCH [--ui] [--from-file FILE] [--ignore-file FILE]
```

| Exit | Meaning |
| --- | --- |
| 0 | Nothing left after the ignore list. It prints nothing. |
| 1 | Messages left. They are printed. |
| 2 | The check could not be made: no log to read, or a bad ignore file. The reason is on stderr. |

The tool's own tests need no simulator: `python3 -B -m unittest discover -s tools` (`-B` keeps `__pycache__` out of the repository).

## What it reads

The log of the simulator the tests ran on (`xcrun simctl spawn <UDID> log show --style ndjson`, with `--device` naming it and `booted` by default) for the process `Grosh`, from the moment the run started. The unit tests run inside that process as the app's test host, so one process covers both suites. It keeps:

- messages at `error` and `fault` level, from Grosh's own `Logger`s (subsystem `Leoxo.Grosh`) and from the frameworks it calls;
- runtime issues, the purple ones. The system logs these as faults in the subsystem `com.apple.runtime-issues`, with the framework as the category (`SwiftUI`). The fault level catches them, and that subsystem is also read at any level.

It also reads the unit tests' marks (subsystem `Leoxo.GroshTests`, category `Tests`, messages `begin <Suite>/<test>` and `end <Suite>/<test>`, and `begin <Suite>` and `end <Suite>` around each suite) to say which test was running. Each suite's `@Suite(.namedInTheLog)` trait logs them (`GroshTests/NamedInTheLog.swift`). With `--ui` it also reads the UI smoke walk's step log (subsystem `Leoxo.GroshUITests`, category `Steps`, messages `begin <step>` and `end <step>`) to say where each message happened. It reads the simulator the tests ran on, which tools/check names with `--device`. The unit tests run on that one simulator too (`Grosh.xctestplan` runs them without clones). That simulator has to be booted when it reads: tools/check boots it when it is down, and shuts it down after the run. When it is still not booted, tools/check skips this check and says so.

## Reading a failure

```
The app logged errors, faults or runtime issues that tools/check-logs.ignore does not cover. See docs/agents/log-check.md.
  Transactions → open a transaction: [SwiftUI] Publishing changes from within view updates is not allowed, this will cause undefined behavior. ×3
  after Home → open: [Import] Could not read the file
  04:54:20  [LayoutConstraints] Unable to simultaneously satisfy constraints. …
```

Each line is `where: [category] message ×count`.

- **Where.** `ReimbursementTests/deletingAReimbursementDoesNotDeleteItsExpense()` is the unit test that was running when the message was logged, and `ReimbursementTests` alone means its suite was running but none of its tests, as while the suite is set up. `Transactions → open a transaction` is the smoke walk's step that was active (the innermost, if steps nest). `after Home → open` means nothing was running but a test or step had ended in the two seconds before, so it is most likely its effect. A bare time (`04:54:20`, the clock `log show` prints) means neither: the app's launch as the test host, or a suite without `.namedInTheLog`. The unit tests run one at a time (`Grosh.xctestplan` doesn't run them in parallel), so the name is exact.
- **`[category]`** is what the message was logged under: an area of the app for Grosh's own messages, the framework's area (`SwiftUI`, `LayoutConstraints`) for the system's. The subsystem is not printed; the commands below show it.
- **`×3`** is how often the message was logged. Messages are the same when they match after trimming whitespace, memory addresses aside (`0x600003c2d4a0`). A group names the first step it happened in, not the others.
- A message of several lines is cut to its first line and ends in `…`; a long one is cut at 300 characters. The log has the rest.
- With `--ui`, a last line says when the log held no steps at all: the walk did not run, or its step log did not reach the simulator's log.

A runtime issue is reported by SwiftUI but caused by Grosh: state changed during a view update, a publish off the main thread. Fix it. To find the line, add a Runtime Issue Breakpoint in Xcode (Breakpoints navigator, +) and run the failing step: the app stops where the issue is raised, and the Debug navigator shows the stack.

## Reading the log by hand

From a booted simulator (`--last 10m`, or `--start 'YYYY-MM-DD HH:MM:SS'` in local time):

```
xcrun simctl spawn booted log show --last 10m --style compact \
    --predicate 'process == "Grosh" AND (messageType == error OR messageType == fault OR subsystem == "com.apple.runtime-issues")'
```

Write `messageType == error` without quotes: `log show` does not understand a quoted one. To see the smoke walk's steps among the messages, add `--info` and widen the predicate to `(…) OR (subsystem == "Leoxo.GroshUITests" AND category == "Steps")`. A log saved with `--style ndjson` replays through the tool (`tools/check-logs --since 0 --from-file grosh.ndjson`), the quick way to try an ignore entry without rerunning the tests.

From a device (the check never reads one): in Console.app select the device in the sidebar, click Start, and filter on the process `Grosh`. The Type column shows errors in yellow and faults in red. Or collect an archive and read it with `log show`:

```
sudo log collect --device --last 10m --output Grosh.logarchive
log show --archive Grosh.logarchive --predicate 'process == "Grosh"'
```

## When an ignore entry is justified

`tools/check-logs.ignore` lists messages to leave out: a JSON list, each entry a `pattern` and a `reason`. An entry is justified when the message is **system noise Grosh cannot fix**: it comes from the system (the keyboard, networking, CoreTelephony, auto layout inside the system keyboard), no code of ours causes it or could avoid it, and the pattern is narrow enough that it cannot hide anything else.

Not justified:

- A message Grosh logged itself (subsystem `Leoxo.Grosh`). Fix the cause. A path a test takes on purpose, such as a bad import file, is not an error to log: log it at `notice`, or not at all.
- A runtime issue (`[SwiftUI] …`). It is Grosh's bug even though a framework prints it.
- A message that is "always there", "flaky" or unexplained. Find out what it is first.
- A pattern wider than the one message: a whole category, or `.*`. Name the system component or quote the text.

An entry (made up, to show the format):

```json
{"pattern": "\\[CoreTelephony\\] .* carrier", "reason": "The system looks for a SIM carrier the simulator does not have. Seen on iOS 26.4."}
```

The pattern is a Python regular expression, searched anywhere in the message as printed (`[category] text`) and case-sensitive. Brackets need a backslash and JSON needs each backslash doubled; `(?s)` lets `.` cross lines. The `reason` is one line: which system component logs it, and why Grosh cannot change that. The tool refuses to run when an entry has no reason, no pattern, an invalid pattern, or a pattern that matches an empty message (so would ignore everything). Adding an entry is a change to review, like a benchmark budget: quote the message in the commit.

## On a Mac

The check has run on a Mac16,7 (Apple M4 Pro) with Xcode 27.1 and the iPhone 17 Pro simulator on iOS 27.0, and on CI (Xcode 26.4, iOS 26.4). A throwaway test that logged a fault (`Logger(subsystem: "Leoxo.Grosh", category: "Probe").fault("probe")`) failed the run with `<Suite>/<test>(): [Probe] probe`, so the check sees the app's messages and names the test. The smoke walk's step names and the tests' names come through public. SwiftUI's configuration warnings arrive as faults of `com.apple.SwiftUI` (`[Invalid Configuration] … tried to update multiple times per frame`), so the fault level catches them whether or not they also reach `com.apple.runtime-issues`.

Each entry in `tools/check-logs.ignore` was checked against the system before it went in: a message that Apple's own apps log on the same simulator, or one that a UI test logs when it only launches Grosh while the same launch without XCTest does not, is system noise. Messages Grosh's own views cause stay out of the list.
