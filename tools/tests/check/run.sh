#!/usr/bin/env bash
#
# Checks tools/check without Xcode: each test runs a copy of it against the stand-ins in fakes/ for xcodebuild, xcrun
# and tools/check-logs, which play back the JSON in fixtures/ the way simctl and xcresulttool print it.
#
#   tools/tests/check/run.sh

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/grosh-check-tests.XXXXXX") || exit 1
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tmp"
lock=$work/tmp/grosh-tools-check.lock

passed=0
failed=0
problems=()
said=
status=
repo=

# A repository with just what tools/check reads, and a tools/check-logs that records how it was called.
make_repo() {
    local repo=$work/$1
    mkdir -p "$repo/tools" "$repo/Grosh.xcodeproj" "$repo/GroshTests"
    cp "$here/../../check" "$repo/tools/check"
    cp "$here/fakes/check-logs" "$repo/tools/check-logs"
    printf '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.4;\n' >"$repo/Grosh.xcodeproj/project.pbxproj"
    : >"$repo/GroshTests/ReimbursementTests.swift"
    : >"$repo/GroshTests/AmountEntryTests.swift"
    echo "$repo"
}

# run <repo> [FAKE_…=… or GROSH_…=…]... [argument]...: runs that repository's tools/check with the fakes first on PATH,
# keeping its exit status in $status and its output in $said, with each duration written as "Ns".
run() {
    local in=$1 settings
    settings=()
    shift
    while [ $# -gt 0 ]; do
        case $1 in
            FAKE_*=* | GROSH_*=*) settings+=("$1") ;;
            *) break ;;
        esac
        shift
    done
    said=$(cd "$in" && env PATH="$here/fakes:$PATH" TMPDIR="$work/tmp" FAKE_CALLS="$in/calls" FAKE_ROOT="$in" \
        ${settings[@]+"${settings[@]}"} "$in/tools/check" "$@" 2>&1)
    status=$?
    said=$(printf '%s\n' "$said" | sed -E 's/ in [0-9]+s/ in Ns/')
}

fails() { problems+=("$1"); }
exits() { [ "$status" = "$1" ] || fails "exited $status, not $1"; }
says() {
    local line
    for line in "$@"; do
        printf '%s\n' "$said" | grep -qxF -- "$line" || fails "printed no line: $line"
    done
}
says_like() { printf '%s\n' "$said" | grep -qxE -- "$1" || fails "printed no line like: $1"; }
never_says() { ! printf '%s\n' "$said" | grep -qF -- "$1" || fails "printed: $1"; }
prints_lines() {
    local count
    count=$(printf '%s\n' "$said" | wc -l | tr -d ' ')
    [ "$count" = "$1" ] || fails "printed $count lines, not $1"
}
called() { grep -qF -- "$1" "$repo/calls" 2>/dev/null || fails "made no call with: $1"; }
called_like() { grep -qE -- "$1" "$repo/calls" 2>/dev/null || fails "made no call like: $1"; }
never_called() { ! grep -qF -- "$1" "$repo/calls" 2>/dev/null || fails "made a call with: $1"; }

test_case() {
    local name=$1
    problems=()
    said=
    "$2"
    never_says "Test Case '"
    [ ! -e "$lock" ] || fails "left the lock behind"
    rm -rf "$lock"
    if [ ${#problems[@]} -eq 0 ]; then
        passed=$((passed + 1))
        echo "ok   $name"
    else
        failed=$((failed + 1))
        echo "FAIL $name"
        printf '       %s\n' "${problems[@]}"
        printf '%s\n' "$said" | sed 's/^/     | /'
    fi
}

without_xcode() {
    local bare=$work/bare-bin stdout
    repo=$(make_repo without-xcode)
    mkdir -p "$bare"
    ln -s "$(command -v bash)" "$bare/bash"
    stdout=$(cd "$repo" && env PATH="$bare" "$repo/tools/check" 2>"$work/stderr")
    status=$?
    said=$(cat "$work/stderr")
    exits 3
    [ -z "$stdout" ] || fails "printed on stdout: $stdout"
    says "tools/check: xcodebuild is not installed, so nothing ran. The tests need Xcode on a Mac."
    prints_lines 1
}

bad_arguments() {
    repo=$(make_repo bad-arguments)
    run "$repo" --only
    exits 64
    run "$repo" --everything
    exits 64
    says "tools/check: unknown argument: --everything"
}

passing() {
    repo=$(make_repo passing)
    run "$repo"
    exits 0
    says "Simulator: iPhone 17 Pro (iOS 26.4)" "412 passed in Ns (9 skipped)"
    says_like "Result: $work/tmp/grosh-check\.[^/]+/Grosh\.xcresult"
    prints_lines 3
    called "xcodebuild -project Grosh.xcodeproj -scheme Grosh -testPlan Grosh -destination platform=iOS Simulator,id=PRO-UDID"
    called "-collect-test-diagnostics never -only-testing:GroshTests test"
    never_called "GROSH_BENCHMARK"
    called_like "^check-logs --since [0-9]+ --device PRO-UDID$"
}

failing() {
    repo=$(make_repo failing)
    mkdir -p "$work/results/Grosh.xcresult"
    run "$repo" GROSH_CHECK_RESULT_DIR="$work/results" FAKE_EXIT=65 FAKE_SUMMARY=summary-failed FAKE_TESTS=tests-failed
    exits 1
    says \
        "FAIL ReimbursementTests/deletingAReimbursementDoesNotDeleteItsExpense(): GroshTests/ReimbursementTests.swift:42: Expectation failed: (net → -1500) == 0" \
        "FAIL ReimbursementTests/deletingAReimbursementDoesNotDeleteItsExpense(): GroshTests/ReimbursementTests.swift:45: Expectation failed: (expense.isDeleted → true) == false The Expense stays when its Reimbursement is deleted" \
        'FAIL AmountEntryTests/parsesTypedAmounts(_:) ["1,5"]: GroshTests/AmountEntryTests.swift:30: Expectation failed: (AmountEntry(typed: "1,5").cents → nil) == 150' \
        "410 passed, 2 failed in Ns (9 skipped)" \
        "Full log: $work/results/xcodebuild.log" \
        "Result: $work/results/Grosh.xcresult"
    prints_lines 7
    [ -s "$work/results/xcodebuild.log" ] || fails "kept no log"
    called_like "^check-logs --since [0-9]+ --device PRO-UDID$"
}

build_failure() {
    repo=$(make_repo build-failure)
    run "$repo" FAKE_EXIT=65 FAKE_BUILD=build-failed
    exits 2
    says "ERROR Grosh/Domain/Reimbursement.swift:41: Cannot find 'reimbursedTotal' in scope" \
        "0 passed, 0 failed in Ns (the build failed)"
    never_says "Command SwiftCompile"
    never_called "check-logs"
}

no_result_bundle() {
    repo=$(make_repo no-result-bundle)
    run "$repo" FAKE_EXIT=70 FAKE_NO_BUNDLE=1
    exits 2
    says "xcodebuild: error: Unable to find a device matching the provided destination specifier" \
        "xcodebuild exited 70 without writing a result bundle."
    says_like "Full log: .*/xcodebuild\.log"
}

unexpected_json() {
    repo=$(make_repo unexpected-json)
    run "$repo" FAKE_TESTS=tests-unexpected
    exits 2
    says 'tools/check could not read the result bundle: the test results have no "testNodes"'
}

ui_tests() {
    repo=$(make_repo ui-tests)
    run "$repo" FAKE_TESTS=tests-ui-passed --ui
    exits 0
    called "-only-testing:GroshTests -only-testing:GroshUITests test"
    called_like "^check-logs --since [0-9]+ --device PRO-UDID --ui$"
}

ui_tests_missing() {
    repo=$(make_repo ui-tests-missing)
    run "$repo" --ui
    exits 1
    says "GroshUITests did not run, though --ui asked for it (see docs/agents/testing.md)."
}

one_suite() {
    repo=$(make_repo one-suite)
    run "$repo" --only ReimbursementTests --only=GroshTests/AmountEntryTests
    exits 0
    called "-only-testing:GroshTests/ReimbursementTests -only-testing:GroshTests/AmountEntryTests test"
}

another_iphone() {
    repo=$(make_repo another-iphone)
    run "$repo" FAKE_SIMCTL=simctl-no-pro
    exits 0
    says "Simulator: iPhone 16e (iOS 26.4)"
    called "id=16E-UDID"
}

no_iphone() {
    repo=$(make_repo no-iphone)
    run "$repo" FAKE_SIMCTL=simctl-no-iphone
    exits 2
    says "No available iPhone simulator runs iOS 26.4 or later. Install it in Xcode > Settings > Components, or add an iPhone in Window > Devices and Simulators."
    never_called "xcodebuild -project"
}

logged_errors() {
    repo=$(make_repo logged-errors)
    run "$repo" FAKE_LOGGED="error Leoxo.Grosh Store: The save could not be completed (2 times)" FAKE_LOGGED_EXIT=1
    exits 1
    says "error Leoxo.Grosh Store: The save could not be completed (2 times)" \
        "412 passed, 0 failed in Ns (9 skipped); Grosh logged errors (tools/check-logs)"
}

two_runs() {
    local first second first_pid first_status tries=0 order
    first=$(make_repo first-worktree)
    second=$(make_repo second-worktree)
    (cd "$first" && exec env PATH="$here/fakes:$PATH" TMPDIR="$work/tmp" FAKE_CALLS="$work/both-calls" \
        FAKE_ROOT="$first" FAKE_SLEEP=3 "$first/tools/check" >"$work/first-output" 2>&1) &
    first_pid=$!
    until [ -s "$lock/pid" ] || [ $tries -ge 100 ]; do
        sleep 0.1
        tries=$((tries + 1))
    done
    repo=$second
    run "$second" FAKE_CALLS="$work/both-calls"
    wait "$first_pid"
    first_status=$?
    exits 0
    [ "$first_status" = 0 ] || fails "the first run exited $first_status"
    says "Waiting for another tools/check run (pid $first_pid, $first)"
    order=$(grep -oE '^xcodebuild (-project|done)' "$work/both-calls" | tr '\n' ' ')
    [ "$order" = "xcodebuild -project xcodebuild done xcodebuild -project xcodebuild done " ] ||
        fails "the two runs' xcodebuilds overlapped: $order"
}

stale_lock() {
    local gone
    repo=$(make_repo stale-lock)
    sleep 0 &
    gone=$!
    wait "$gone"
    mkdir -p "$lock"
    echo "$gone" >"$lock/pid"
    echo "/Users/leo/Grosh/.claude/worktrees/gone" >"$lock/dir"
    run "$repo"
    exits 0
    never_says "Waiting for another tools/check run"
}

not_booted() {
    repo=$(make_repo not-booted)
    run "$repo" FAKE_BOOTED=simctl-none
    exits 0
    says "tools/check-logs skipped: the simulator the tests ran on is not booted, so there is no log to read." \
        "412 passed in Ns (9 skipped)"
    never_called "check-logs"
}

crash_diagnostics() {
    repo=$(make_repo crash-diagnostics)
    run "$repo" GROSH_CRASH_REPORTS="$work/reports" FAKE_CRASH_REPORT=1 FAKE_TESTS=tests-crashed \
        FAKE_SUMMARY=summary-failed FAKE_EXIT=65
    exits 1
    says "FAIL ReimbursementTests/deletingAReimbursementDoesNotDeleteItsExpense(): Test crashed with signal trap." \
        "  0 Grosh NotDeletedTransactions.apply(_:)" \
        "  1 libswiftCore.dylib offset 8192" \
        "  2 Grosh closure #1 in NotDeletedTransactions.init"
    says_like "crash report .*/reports/Grosh-2026-10-23\.ips: EXC_BREAKPOINT \(SIGTRAP\) in Grosh"
    called_like "^check-logs --since [0-9]+ --device PRO-UDID$"
}

test_case "without Xcode, nothing runs and it exits 3" without_xcode
test_case "wrong arguments exit 64" bad_arguments
test_case "a passing run prints three lines and runs the unit tests only" passing
test_case "a failing run prints each failure with its file and line" failing
test_case "a build failure prints each error with its file and line" build_failure
test_case "no result bundle prints xcodebuild's own error" no_result_bundle
test_case "result JSON of an unexpected shape fails loudly" unexpected_json
test_case "--ui runs the UI tests too" ui_tests
test_case "--ui fails when the UI tests did not run" ui_tests_missing
test_case "--only runs the suites named" one_suite
test_case "without an iPhone 17 Pro it picks another iPhone" another_iphone
test_case "without an iPhone it stops before building" no_iphone
test_case "errors Grosh logged fail the run" logged_errors
test_case "a second run waits for the first and says so" two_runs
test_case "a lock left by a run that is gone is taken over" stale_lock
test_case "a simulator that is not booted skips the log check and says so" not_booted
test_case "a crash prints the crashed thread from its crash report" crash_diagnostics

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
