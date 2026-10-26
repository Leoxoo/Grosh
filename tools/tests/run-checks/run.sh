#!/usr/bin/env bash
#
# Checks .claude/hooks/run-checks.sh without Xcode or a model: each test runs the hook on a throwaway repository whose
# tools/check is a stand-in that fails while a Swift file says BROKEN, with the stand-ins in fakes/ for xcodebuild,
# curl (LM Studio answering) and claude (the local model) first on PATH.
#
#   tools/tests/run-checks/run.sh

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
hook=$(cd "$here/../../.." && pwd -P)/.claude/hooks/run-checks.sh
work=$(mktemp -d "${TMPDIR:-/tmp}/grosh-run-checks-tests.XXXXXX") || exit 1
work=$(cd "$work" && pwd -P)
trap 'rm -rf "$work"' EXIT

passed=0
failed=0
problems=()
said=
status=
repo=

# A repository with one Swift file in Grosh/ and one in GroshTests/, and a tools/check that records its calls and fails
# while any Swift file holds BROKEN. FAKE_CHECK_EXIT makes it exit with that status instead.
make_repo() {
    repo=$work/$1
    mkdir -p "$repo/Grosh" "$repo/GroshTests" "$repo/tools"
    printf 'let app = 1\n' >"$repo/Grosh/App.swift"
    printf 'let test = 1\n' >"$repo/GroshTests/AppTests.swift"
    printf 'Grosh\n' >"$repo/README.md"
    cat >"$repo/tools/check" <<'EOF'
#!/usr/bin/env bash
printf 'check\n' >>"$FAKE_CALLS"
if [ -n "${FAKE_CHECK_EXIT:-}" ]; then
    exit "$FAKE_CHECK_EXIT"
fi
if grep -q BROKEN Grosh/*.swift GroshTests/*.swift 2>/dev/null; then
    echo "FAIL AppTests/works(): GroshTests/AppTests.swift:1: Expectation failed"
    echo "1 passed, 1 failed in 1s"
    exit 1
fi
echo "2 passed in 1s"
EOF
    chmod +x "$repo/tools/check"
    (
        cd "$repo" &&
            git init -q &&
            git config user.name Test && git config user.email test@example.com &&
            git add -A && git commit -q -m start
    ) || exit 1
    : >"$work/$1.calls"
}

# hook <stop|prompt> [true|false] [NAME=value]...: runs the hook on $repo the way Claude Code does, with stop_hook_active
# set as given (false by default), keeping its exit status in $status and what it printed on stdout in $said.
hook() {
    local mode=$1 active=false settings=()
    shift
    case ${1:-} in true | false) active=$1 && shift ;; esac
    settings=("$@")
    said=$(printf '{"session_id":"test","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' "$repo" "$active" |
        env -u GROSH_CHECKS_NESTED -u GROSH_LOCAL_FIX -u GROSH_LOCAL_FIX_MODEL \
            PATH="$here/fakes:$PATH" FAKE_CALLS="$work/$(basename "$repo").calls" \
            ${settings[@]+"${settings[@]}"} "$hook" "$mode")
    status=$?
}
stop() { hook stop "$@"; }
prompt() { hook prompt "$@"; }

calls() { grep -c "^$1" "$work/$(basename "$repo").calls"; }
state() { cat "$(cd "$repo" && git rev-parse --path-format=absolute --git-path grosh-checks)/$1" 2>/dev/null; }

# Every file and folder outside .git with its contents, what is staged and the stash list: what the hook must leave
# as it found it when the local model fails.
fingerprint() {
    (
        cd "$repo" &&
            find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r file; do
                printf '%s %s\n' "$(cksum <"$file")" "$file"
            done &&
            find . -path ./.git -prune -o -type d -print | LC_ALL=C sort &&
            git diff --cached &&
            git stash list
    )
}

fails() { problems+=("$1"); }
exits() { [ "$status" = "$1" ] || fails "exited $status, not $1"; }
silent() { [ -z "$said" ] || fails "printed something"; }
says() {
    local text
    for text in "$@"; do
        printf '%s' "$said" | grep -qF -- "$text" || fails "printed nothing with: $text"
    done
}
never_says() { ! printf '%s' "$said" | grep -qF -- "$1" || fails "printed: $1"; }
blocks() { says '{"decision":"block","reason":"The unit tests fail. tools/check reports:'; }
checks() { [ "$(calls check)" = "$1" ] || fails "ran tools/check $(calls check) times, not $1"; }
asks_the_model() { [ "$(calls claude)" = "$1" ] || fails "ran the local model $(calls claude) times, not $1"; }

test_case() {
    local name=$1
    problems=()
    said=
    status=
    "$2"
    exits 0
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

break_the_tests() { printf 'let broken = 1 // BROKEN\n' >>"$repo/Grosh/App.swift"; }

without_xcode() {
    make_repo without-xcode
    break_the_tests
    mkdir -p "$work/empty-bin"
    said=$(printf '{"cwd":"%s"}' "$repo" | env PATH="$work/empty-bin" /bin/bash "$hook" stop)
    status=$?
    silent
    checks 0
}

quiet_without_swift_changes() {
    make_repo quiet
    prompt
    silent
    stop
    silent
    checks 0
    printf 'Grosh, a finance app\n' >"$repo/README.md"
    stop
    silent
    checks 0
}

passing() {
    make_repo passing
    prompt
    printf 'let more = 2\n' >>"$repo/Grosh/App.swift"
    stop
    silent
    checks 1
    stop true
    silent
    checks 1
}

failing() {
    make_repo failing
    prompt
    break_the_tests
    stop GROSH_LOCAL_FIX=0
    blocks
    says "FAIL AppTests/works(): GroshTests/AppTests.swift:1: Expectation failed" "Fix the failures before you finish."
    never_says "A local model"
    checks 1
}

new_untracked_swift_file() {
    make_repo untracked
    prompt
    printf 'let x = 1 // BROKEN\n' >"$repo/GroshTests/NewTests.swift"
    stop GROSH_LOCAL_FIX=0
    blocks
}

three_failures() {
    make_repo three-failures
    prompt
    break_the_tests
    stop false GROSH_LOCAL_FIX=0
    blocks
    stop true GROSH_LOCAL_FIX=0
    blocks
    stop true GROSH_LOCAL_FIX=0
    says '{"systemMessage":"The unit tests still fail after 3 tries, so the agent has stopped.'
    says "FAIL AppTests/works()"
    never_says '"decision":"block"'
    checks 3
    stop true GROSH_LOCAL_FIX=0
    silent
    checks 3
    printf 'let again = 1\n' >>"$repo/Grosh/App.swift"
    stop true GROSH_LOCAL_FIX=0
    blocks
    checks 4
}

user_message_restarts_the_count() {
    make_repo restart
    prompt
    break_the_tests
    stop false GROSH_LOCAL_FIX=0
    stop true GROSH_LOCAL_FIX=0
    stop false GROSH_LOCAL_FIX=0
    blocks
    stop true GROSH_LOCAL_FIX=0
    blocks
    [ "$(state failed-stops)" = 2 ] || fails "counted $(state failed-stops) failed stops, not 2"
}

check_without_xcodebuild() {
    make_repo check-without-xcodebuild
    prompt
    break_the_tests
    stop FAKE_CHECK_EXIT=3
    silent
    checks 1
}

long_report_is_cut() {
    make_repo long-report
    prompt
    break_the_tests
    cat >"$repo/tools/check" <<'EOF'
#!/usr/bin/env bash
for i in $(seq 1 100); do echo "FAIL Suite/test$i(): GroshTests/AppTests.swift:$i: failed"; done
exit 1
EOF
    stop GROSH_LOCAL_FIX=0
    blocks
    says "FAIL Suite/test80()" "(20 more lines not shown)"
    never_says "FAIL Suite/test81()"
}

local_fix_turned_off() {
    make_repo local-off
    prompt
    break_the_tests
    stop GROSH_LOCAL_FIX_MODEL=model GROSH_LOCAL_FIX=0 FAKE_CLAUDE=fix
    blocks
    asks_the_model 0
    [ "$(calls curl)" = 0 ] || fails "asked LM Studio with the local fix off"
}

no_model_named() {
    make_repo no-model
    prompt
    break_the_tests
    stop FAKE_CLAUDE=fix
    blocks
    asks_the_model 0
    state local-fixes.log | grep -qF "skipped: no GROSH_LOCAL_FIX_MODEL" || fails "logged no skipped attempt"
}

lm_studio_down() {
    make_repo lm-studio-down
    prompt
    break_the_tests
    stop GROSH_LOCAL_FIX_MODEL=model FAKE_CURL_EXIT=7 FAKE_CLAUDE=fix
    blocks
    [ "$(calls curl)" = 1 ] || fails "asked LM Studio $(calls curl) times, not once"
    asks_the_model 0
    never_says "A local model"
}

local_fix_that_works() {
    make_repo local-fix-works
    prompt
    break_the_tests
    stop GROSH_LOCAL_FIX_MODEL=model FAKE_CLAUDE=fix
    silent
    asks_the_model 1
    checks 2
    grep -q "^claude GROSH_CHECKS_NESTED=1 -p " "$work/local-fix-works.calls" || fails "ran the model without GROSH_CHECKS_NESTED"
    grep -q BROKEN "$repo/Grosh/App.swift" && fails "undid the fix"
    prompt
    says '"hookEventName":"UserPromptSubmit"' "a local model fixed them before you saw" "Grosh/App.swift" "Line three."
    prompt
    silent
    stop true
    silent
    checks 2
}

failed_attempt_is_undone() {
    make_repo local-fix-fails
    # The developer's own work in progress: a stash, an edit to a tracked file, a staged change and an untracked file.
    printf 'stashed\n' >>"$repo/README.md"
    (cd "$repo" && git stash -q)
    printf 'let test = 2 // in progress\n' >"$repo/GroshTests/AppTests.swift"
    printf 'Grosh, staged\n' >"$repo/README.md"
    (cd "$repo" && git add README.md)
    printf 'let draft = 1\n' >"$repo/Grosh/Draft.swift"
    prompt
    break_the_tests
    local before
    before=$(fingerprint)

    stop GROSH_LOCAL_FIX_MODEL=model FAKE_CLAUDE=mess
    blocks
    says "A local model tried first and did not fix them, so its changes were undone. It said:" "Line three." \
        "local-fix.diff" "Grosh/New/Deep/Made.swift"
    asks_the_model 1
    [ "$(fingerprint)" = "$before" ] || fails "left the worktree, the index or the stash list changed"
    [ ! -e "$repo/Grosh/New" ] || fails "left the folders the model made"
    state local-fix.diff | grep -qF "struct Made {}" || fails "saved no diff of the attempt"
    state local-fixes.log | grep -qF "no" || fails "logged no failed attempt"
}

model_that_changes_nothing() {
    make_repo local-fix-nothing
    prompt
    break_the_tests
    stop GROSH_LOCAL_FIX_MODEL=model FAKE_CLAUDE=nothing
    blocks
    says "A local model tried first and changed nothing. It said:" "Line three."
    never_says "local-fix.diff"
}

local_attempt_counts_toward_the_limit() {
    make_repo local-fix-limit
    prompt
    break_the_tests
    stop false GROSH_LOCAL_FIX_MODEL=model FAKE_CLAUDE=mess
    blocks
    stop true GROSH_LOCAL_FIX_MODEL=model FAKE_CLAUDE=mess
    blocks
    never_says "A local model"
    stop true GROSH_LOCAL_FIX_MODEL=model FAKE_CLAUDE=mess
    says "still fail after 3 tries"
    asks_the_model 1
}

nested_session_is_left_alone() {
    make_repo nested
    prompt
    break_the_tests
    stop GROSH_CHECKS_NESTED=1
    silent
    checks 0
}

test_case "without xcodebuild it does nothing" without_xcode
test_case "without Swift changes it runs nothing and says nothing" quiet_without_swift_changes
test_case "a passing run says nothing and is not run again for the same Swift" passing
test_case "a failing run blocks the stop with tools/check's failure lines" failing
test_case "a new untracked Swift file counts as a change" new_untracked_swift_file
test_case "the third failure in a row lets the agent stop and shows the user" three_failures
test_case "a stop after the user's message starts the count again" user_message_restarts_the_count
test_case "tools/check finding no xcodebuild says nothing" check_without_xcodebuild
test_case "a long report is cut to 80 lines" long_report_is_cut
test_case "GROSH_LOCAL_FIX=0 turns the local fix off" local_fix_turned_off
test_case "without GROSH_LOCAL_FIX_MODEL the local fix is skipped and logged" no_model_named
test_case "with LM Studio down it blocks straight away" lm_studio_down
test_case "a local fix that works ends the turn and tells the agent once, at the next message" local_fix_that_works
test_case "a failed local attempt leaves the worktree, index and stash list as they were" failed_attempt_is_undone
test_case "a local model that changes nothing is reported as such" model_that_changes_nothing
test_case "the local attempt runs once and counts toward the three failures" local_attempt_counts_toward_the_limit
test_case "the local model's own session is left alone" nested_session_is_left_alone

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
