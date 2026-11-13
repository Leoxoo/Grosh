# Benchmarks and budgets

`GroshTests/PerformanceBenchmarks.swift` times what the user waits for on **the 16k store** (see `architecture.md`): launch, opening each screen, scrolling, saving, searching and stepping back to an older month. Each timed step has a **budget** in `GroshTests/BenchmarkBudgets.swift`: the most its median may be, in milliseconds. A step over its budget fails the run, so a slowdown shows up as a failure instead of waiting for someone to compare `BENCH` lines by hand before and after a change.

The budgets belong to one machine (see [Budgets belong to one machine](#budgets-belong-to-one-machine)). A normal test run skips the benchmarks: they run only when `GROSH_BENCHMARK` is set, and CI doesn't run them.

## Run them

```
TEST_RUNNER_GROSH_BENCHMARK=1 xcodebuild test -scheme Grosh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    SWIFT_OPTIMIZATION_LEVEL=-O -parallel-testing-enabled NO -only-testing:GroshTests/PerformanceBenchmarks
```

- Use an optimized build, as above. A build without optimization is much slower, so the run counts it as another setup and only warns.
- The store is made on the first run of the day, which takes a few minutes.
- `TEST_RUNNER_GROSH_BENCHMARK_OUT=/absolute/path` adds the lines a run reports (its setup, each step, any warnings and the summary) to that file too, after whatever is already there.

A run prints:

```
BENCH setup: <Mac model> (<chip>) / <iPhone model> simulator / iOS <version> (<build>) / Xcode <version> (<build>) / optimized
BENCH open Home          median   212.00 ms   min   200.10   max   230.40   (n=7)   budget   150.00 ms (+41%)
...
BENCH summary: 18 steps timed, 1 over budget: open Home: 212 ms > budget 150 ms (+41%)
```

Each step's line ends with its budget and how far its median is from it: `(+41%)` is 41% over, `(-25%)` is 25% under. The last line lists every step over its budget, worst first. It is made from the steps that were timed, not from which test ran last, so it is the same whatever order the tests run in (a suite trait, `.checkingBudgets`, prints it once after the suite's last test).

## Read a failure

| What it says | What it means | What to do |
| --- | --- | --- |
| `open Home: 212 ms > budget 150 ms (+41%)` | The median of the step's timed runs is 41% over its budget. | Treat it as a regression. Run it again to rule out noise, then find what got slower, benchmarking before and after (`architecture.md`: "Measure what you touch"). Raise the budget only when the slowdown is deliberate (below). |
| `no budget recorded for open Home (median 212 ms): add it to GroshTests/BenchmarkBudgets.swift` | The step has no budget: it is new, or its name changed. The median is from this one run. | Record a budget for it (below). This fails on every setup, because it is about the code, not the machine. |
| `BENCH warning: open Home: 212 ms > budget 150 ms (+41%)` | The numbers of the first message, but this is not the setup the budgets were measured on, so the run passes. | Nothing, unless the budgets should apply here. The `BENCH setup:` and `BENCH warning:` lines at the top of the run show how this setup differs from the recorded one. |

A failure is recorded at the line that timed the step, so the test report points at it. A step that fails once and passes on the next run of an unchanged tree has too little headroom: widen its budget instead of re-running until it passes.

## Record or change a budget

The budgets are the `steps` table in `GroshTests/BenchmarkBudgets.swift`, one `"<step name>": <milliseconds>,` for each step, plus `recordedSetup`. A budget is the step's measured median plus headroom for noise.

1. **Pick the setup.** Record on the Mac, simulator, OS and Xcode you run the benchmarks on; the `BENCH setup:` line says what that is. Plug the Mac in, quit other apps and let nothing else build, so the runs are quiet.
2. **Run at least five times, into one file.** While steps have no budget they fail, but each is still timed.

   ```
   rm -f /tmp/grosh-bench.txt
   for run in 1 2 3 4 5; do
       TEST_RUNNER_GROSH_BENCHMARK=1 TEST_RUNNER_GROSH_BENCHMARK_OUT=/tmp/grosh-bench.txt \
           xcodebuild test -scheme Grosh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           SWIFT_OPTIMIZATION_LEVEL=-O -parallel-testing-enabled NO -only-testing:GroshTests/PerformanceBenchmarks
   done
   ```

3. **Take each step's median of the runs' medians.**

   ```
   sed -nE 's/^BENCH (.+[^ ]) +median +([0-9.]+) ms +min.*/\1|\2/p' /tmp/grosh-bench.txt \
       | LC_ALL=C sort -t '|' -k1,1 -k2,2n \
       | awk -F '|' '
           function flush() { if (n) printf "%10.2f %10.2f  %s\n", v[int((n + 1) / 2)], v[n], name }
           $1 != name { flush(); name = $1; n = 0 }
           { v[++n] = $2 }
           END { flush() }'
   ```

   The first column is that median of medians, the second is the slowest run's median, then the step's name.
4. **Add headroom.** The slowest median is a floor: a budget under it would have failed one of those runs on an unchanged tree. Above that, pick the smallest headroom with which five more back-to-back runs of the unchanged tree all pass. Too little and ordinary noise fails the run; too much and a real regression fits under the budget. A noisy step can take more headroom than a quiet one, because the table holds each step's final number.
5. **Write them down.** Copy each step's name from its `BENCH` line or failure message, since names hold characters like `½` and quotes that are easy to mistype. Set `recordedSetup` to the text after `BENCH setup: `, exactly.
6. **Check.** Run five times in a row with the table in place. All five must pass, and each `BENCH summary:` must say `all within budget`. If a step fails, widen its budget and run the five again.
7. **Commit** the table with the before → after numbers in the message, as `architecture.md` asks and cc60ff5 and d91cfa8 do: each step's median and its budget, before → after.

What to change, and when:

- **A change makes a step faster.** Lower its budget in the same commit, at the new median plus the same headroom, so the gain can't quietly be lost.
- **A change makes a step slower on purpose.** Raise its budget in the same commit and say why in the message.
- **A new step.** Add its line only. The other budgets and `recordedSetup` stay.
- **A new setup** (another Mac, or an update of Xcode, the simulator or the OS). Record every budget and `recordedSetup` again in one commit, because the old numbers say nothing about the new setup.

## Budgets belong to one machine

Milliseconds only mean something on the Mac and simulator they were measured on, so `recordedSetup` holds the setup, and a run compares its own with it. On the recorded setup a step over its budget fails. On any other it prints `BENCH warning:` with the same numbers and the run passes.

Nothing is set by hand; the run reads its setup from the machine. The simulator is a process on the Mac, so most of it is there to read:

- **The Mac**: its model identifier and chip, from `sysctl` (`hw.model`, `machdep.cpu.brand_string`), which the simulator reads from the Mac.
- **The simulated iPhone**: its model identifier, from `SIMULATOR_MODEL_IDENTIFIER`. Its name isn't used, because Xcode renames a clone of the simulator.
- **The OS**: `ProcessInfo`'s `operatingSystemVersion`, and the runtime's build from `SIMULATOR_RUNTIME_BUILD_VERSION` when that is set.
- **Xcode**: its version and build, from the `DTXcode` and `DTXcodeBuild` entries Xcode writes into the Info.plist of what it builds.
- **The build**: `optimized` or `unoptimized`.

A part that can't be read shows as `unknown Mac`, `unknown Xcode` or `not a simulator`, and reads the same on every run, so the comparison still holds. A different Mac, an update of Xcode, the simulator or the OS, and an unoptimized build each make a run another setup. If warnings appear on the Mac the budgets were measured on, compare the two setup lines to see which part changed.

## Where the code is

- `GroshTests/BenchmarkBudgets.swift` holds the table and `recordedSetup`, reads the setup, compares each step with its budget and writes the summary. Its `BenchmarkBudgetTests` run in every normal test run, on made-up timings, and also check that a table that has budgets names the setup they were measured on.
- `GroshTests/PerformanceBenchmarks.swift` times the steps. `time` and `report` print each one with its budget and hand it to the budgets.

## Where things stand

The budgets were recorded on 25 October 2026, on the setup `recordedSetup` names: a Mac16,7 (Apple M4 Pro), the iPhone 17 Pro simulator (iPhone18,1) with iOS 27.0 (24A434), Xcode 27.1 (27A9275), optimized. Five runs gave each step's numbers, and five more with the table in place all passed.

**The headroom** is 25% over the slowest of the five medians, and at least 5 ms over it: `budget = max(slowest × 1.25, slowest + 5)`, rounded up to a whole millisecond. The 5 ms floor is for the short steps (9 to 30 ms), where a few milliseconds of noise is a large share. Use the same rule when you record a step again.
