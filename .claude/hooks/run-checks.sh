#!/bin/bash
#
# Runs the unit tests when the agent stops after editing Swift, and hands the agent only the
# failures. .claude/settings.json registers it twice.
#
# run-checks.sh, the Stop hook ("timeout": 300). When a .swift file under Grosh/ or GroshTests/
# differs from the tree of the last passing run, it runs tools/check, which runs the unit tests.
# A pass records the tree and adds nothing to the conversation. A failure blocks the stop and hands
# the agent tools/check's failure lines. The third failure in a row lets the agent stop and shows
# the user what still fails, and the hook then stays quiet until the Swift changes again. A stop
# that follows a message from the user (stop_hook_active is false) starts the count again. When
# tools/check runs out of time, waiting on another session's run included, the agent stops with a
# one-line note. Where xcodebuild is not installed (cloud and Linux sessions) the hook does nothing.
#
# run-checks.sh prompt, the UserPromptSubmit hook. It hands the agent, once, the note a local fix
# left. Before any run has passed, it records the tree as it is at the first prompt, so that a turn
# without Swift changes stays quiet.
#
# The local fix. On the first failure in a row, before blocking, a local model served by LM Studio
# on localhost:1234 gets one headless attempt, capped at 300 seconds including its tools/check rerun
# and by what is left of the hook's own 300 seconds. If LM Studio does not answer within 2 seconds,
# the hook blocks straight away. The local model may read, edit files under Grosh/ and GroshTests/
# and run tools/check, and is refused anything else. When tools/check passes after the attempt, the
# turn ends as usual, and on the user's next message the agent learns which files changed and why.
# Otherwise the worktree goes back to a snapshot taken just before the attempt, the attempt's full
# diff is saved, and the agent gets the failure lines with the local model's summary, its diffstat
# and the path of the diff. The snapshot is a tree written from a temporary index (git add -A, then
# git write-tree), so it holds untracked files too and leaves the real index and the shared stash
# list alone. Ignored files are not part of it. To turn the local fix off, set GROSH_LOCAL_FIX=0,
# for example with
#   "env": { "GROSH_LOCAL_FIX": "0" }
# at the top level of .claude/settings.json.
#
# State lives in the git directory, at `git rev-parse --git-path grosh-checks`, so it is never
# tracked and each worktree keeps its own:
#   baseline-tree    the tree of the last passing run, or of the first prompt before any run passed
#   failed-stops     how many stops in a row the tests failed
#   given-up-tree    the tree whose failures were last shown to the user
#   note             the note waiting for the user's next message
#   local-fix.diff   the full diff of the last local attempt that failed
#   local-fixes.log  one line per local attempt: date, whether it fixed the tests, seconds, failure
# with the output of the last runs beside them (check.out, local-fix.out, local-fix.err and so on).

hook_timeout=300  # The Stop hook's "timeout" in .claude/settings.json.
attempt_limit=300 # The local attempt's cap, its tools/check rerun included.
model_minimum=60  # The local model isn't started with less time than this.
failure_limit=3
local_url=http://localhost:1234
local_model=qwen/qwen3.8-27b
swift_paths=('Grosh/*.swift' 'GroshTests/*.swift')

# The local model's own session runs with GROSH_CHECKS_NESTED set, so its hooks leave it alone.
[ -n "$GROSH_CHECKS_NESTED" ] && exit 0
command -v xcodebuild >/dev/null 2>&1 || exit 0

mode=${1:-stop}
case $mode in stop | prompt) ;; *) exit 0 ;; esac
started=$(date +%s)
deadline=$((started + hook_timeout - 20))
input=$(cat)

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd" *: *"\([^"]*\)".*/\1/p' | head -n 1)
[ -d "$cwd" ] || cwd=$PWD
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && cd "$top" && [ -x tools/check ] || exit 0

git_path() {
  local path
  path=$(git rev-parse --git-path "$1") || return 1
  case $path in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$top/$path" ;;
  esac
}

state=$(git_path grosh-checks) && index=$(git_path index) && mkdir -p "$state" || exit 0
exec 2>"$state/$mode.log"

read_state() { cat "$state/$1" 2>/dev/null; }
write_state() { printf '%s\n' "$2" >"$state/$1.new" && mv -f "$state/$1.new" "$state/$1"; }

# Prints the id of a tree that holds the worktree as it is now, untracked files included. It is
# built in a temporary index, so the real one is left alone. With paths, only those come from the
# worktree and the rest is as staged.
worktree_tree() {
  local tmp="$state/index.$$" tree=""
  rm -f "$tmp"
  cp "$index" "$tmp" 2>/dev/null
  if GIT_INDEX_FILE=$tmp git add -A -- "$@" >/dev/null 2>&1 ||
    GIT_INDEX_FILE=$tmp git add -A >/dev/null 2>&1; then
    tree=$(GIT_INDEX_FILE=$tmp git write-tree)
  fi
  rm -f "$tmp"
  [ -n "$tree" ] && printf '%s\n' "$tree"
}

same_swift() { git diff-tree --quiet -r "$1" "$2" -- "${swift_paths[@]}" >/dev/null 2>&1; }

json_string() {
  printf '%s' "$1" | tr -d '\000-\010\013-\037' |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$(printf '\t')/\\\\t/g" |
    awk 'BEGIN { printf "\"" } NR > 1 { printf "%s", "\\n" } { printf "%s", $0 } END { printf "\"" }'
}

block() {
  printf '{"decision":"block","reason":%s}\n' "$(json_string "$1")"
  exit 0
}

tell_user() {
  printf '{"systemMessage":%s}\n' "$(json_string "$1")"
  exit 0
}

timeout_tool=$(command -v timeout || command -v gtimeout)
child=""
watchdog=""

# Runs a command with stdin closed, its output and its errors in two files, which may be the same
# one, and stops it, with everything it started, after a number of seconds. Returns the command's
# status, or 124 when it ran out of time.
run_limited() {
  local seconds=$1 out=$2 err=$3 begun status
  shift 3
  : >"$out"
  : >"$err"
  [ "$seconds" -gt 0 ] || return 124
  begun=$(date +%s)
  if [ -n "$timeout_tool" ]; then
    "$timeout_tool" -k 5 "$seconds" "$@" >>"$out" 2>>"$err" </dev/null &
    child=$!
  else
    # macOS has no timeout: run the command in a process group of its own and stop the group.
    set -m
    "$@" >>"$out" 2>>"$err" </dev/null &
    child=$!
    (
      sleep "$seconds"
      kill -TERM -- "-$child" || kill -TERM "$child"
      sleep 5
      kill -KILL -- "-$child" || kill -KILL "$child"
    ) >/dev/null 2>&1 </dev/null &
    watchdog=$!
    set +m
  fi
  wait "$child"
  status=$?
  [ -n "$watchdog" ] && kill -- "-$watchdog" 2>/dev/null
  child=""
  watchdog=""
  if [ "$status" -ne 0 ] && [ $(($(date +%s) - begun)) -ge "$seconds" ]; then
    return 124
  fi
  return "$status"
}

stop_child() {
  [ -n "$child" ] || return
  if [ -n "$timeout_tool" ]; then
    kill -TERM "$child"
  else
    kill -TERM -- "-$child" || kill -TERM "$child"
    [ -n "$watchdog" ] && kill -- "-$watchdog"
  fi
  wait "$child"
} 2>/dev/null

# tools/check's report, cut to 80 lines.
failure_lines() {
  local count
  count=$(($(wc -l <"$1")))
  head -n 80 "$1"
  [ "$count" -le 80 ] || echo "($((count - 80)) more lines not shown)"
}

passed() {
  write_state baseline-tree "$1"
  write_state failed-stops 0
  rm -f "$state/given-up-tree"
  exit 0
}

snapshot=""

# Removes the directories above a file the local attempt created, up to the first one that was
# there before the attempt.
remove_new_dirs() {
  local dir=$1
  while [ "${dir%/*}" != "$dir" ]; do
    dir=${dir%/*}
    grep -qxF "./$dir" "$state/dirs-before" && return
    rmdir -- "$dir" 2>/dev/null || return
  done
}

# Puts the worktree back to the snapshot: what the attempt changed or deleted comes back from it,
# and what it created is removed. Returns 1 if the worktree still differs from the snapshot.
restore_snapshot() {
  local after=${1:-$(worktree_tree)} meta path tmp="$state/index.restore.$$"
  git diff-tree -r -z --no-renames "$snapshot" "$after" >"$state/restore.raw" || return 1
  : >"$state/restore.list"
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    set -- $meta
    # Leave nested repositories and worktrees alone.
    if [ "${1#:}" = 160000 ] || [ "$2" = 160000 ]; then
      continue
    fi
    if [ "$5" = A ]; then
      rm -f -- "$path"
      remove_new_dirs "$path"
    else
      printf '%s\0' "$path" >>"$state/restore.list"
    fi
  done <"$state/restore.raw"
  if [ -s "$state/restore.list" ]; then
    GIT_INDEX_FILE=$tmp git read-tree "$snapshot" &&
      GIT_INDEX_FILE=$tmp git checkout-index -f -z --stdin <"$state/restore.list"
  fi
  rm -f "$tmp"
  cmp -s "$index" "$state/index-before" || cp "$state/index-before" "$index"
  [ "$(worktree_tree)" = "$snapshot" ]
}

on_signal() {
  stop_child
  [ -n "$snapshot" ] && restore_snapshot
  exit 0
}
trap on_signal TERM INT HUP

log_attempt() {
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$2" "$(head -n 1 "$state/check.out")" \
    >>"$state/local-fixes.log"
}

local_prompt() {
  printf '%s\n' \
    "tools/check builds Grosh and runs its unit tests. It reports these failures:" \
    "" \
    "$report" \
    "" \
    "Fix them by editing the Swift code under Grosh/ or GroshTests/. Do not delete or disable tests." \
    "Run tools/check to confirm that everything passes. Do not run any other command." \
    "When you are done, reply with two or three short lines that say what you changed and why."
}

local_report=""

# Lets the local model try the fix. Ends the hook quietly if the tests pass afterwards. Otherwise
# it undoes the attempt and leaves what the agent needs to know about it in local_report.
try_local_fix() {
  [ "${GROSH_LOCAL_FIX:-1}" != 0 ] || return
  command -v claude >/dev/null 2>&1 || return
  curl -s -o /dev/null --noproxy '*' -m 2 "$local_url/v1/models" || return

  local began attempt_end model_end taken status after outcome summary stat seconds
  began=$(date +%s)
  attempt_end=$((began + attempt_limit))
  [ "$attempt_end" -le "$deadline" ] || attempt_end=$deadline
  # Keep as long for the rerun as the first run took.
  model_end=$((attempt_end - check_seconds - 10))
  if [ $((model_end - began)) -lt "$model_minimum" ]; then
    log_attempt "skipped: $((attempt_end - began)) s left" 0
    return
  fi

  taken=$(worktree_tree) &&
    find . -name .git -prune -o -type d -print >"$state/dirs-before" &&
    cp "$index" "$state/index-before" || return
  snapshot=$taken

  run_limited $((model_end - began)) "$state/local-fix.out" "$state/local-fix.err" \
    env ANTHROPIC_BASE_URL="$local_url" ANTHROPIC_AUTH_TOKEN=lmstudio GROSH_CHECKS_NESTED=1 \
    claude -p "$(local_prompt)" --model "$local_model" --permission-mode dontAsk \
    --allowedTools "Read,Glob,Grep,Edit(Grosh/**),Edit(GroshTests/**),Write(Grosh/**),Write(GroshTests/**),Bash(tools/check),Bash(tools/check *)"
  status=$?
  after=$(worktree_tree)
  outcome=no
  if [ "$after" = "$snapshot" ]; then
    outcome="no: changed nothing"
  elif [ "$status" -eq 124 ]; then
    outcome="no: out of time"
  else
    run_limited $((attempt_end - $(date +%s))) "$state/recheck.out" "$state/recheck.out" tools/check
    case $? in
      0) outcome=yes ;;
      124) outcome="no: out of time" ;;
    esac
  fi
  seconds=$(($(date +%s) - began))
  summary=$(grep -v '^[[:space:]]*$' "$state/local-fix.out" | tail -n 3 | cut -c 1-300)
  if [ -z "$summary" ]; then
    case $outcome in
      *time) summary="(It ran out of time before it replied.)" ;;
      *) summary="(It gave no reply.)" ;;
    esac
  fi
  stat=$(git diff-tree -r --stat "$snapshot" "$after")
  log_attempt "$outcome" "$seconds"

  if [ "$outcome" = yes ]; then
    {
      [ -s "$state/note" ] && echo
      echo "After your last turn the unit tests failed, and a local model fixed them before you saw" \
        "the failures. tools/check passes now. It changed:"
      echo "$stat"
      echo "It said:"
      echo "$summary"
    } >>"$state/note"
    snapshot=""
    passed "$after"
  fi

  if [ "$outcome" = "no: changed nothing" ]; then
    local_report="

A local model tried first and changed nothing. It said:
$summary"
  else
    git diff-tree -r -p --binary "$snapshot" "$after" >"$state/local-fix.diff"
    local_report="

A local model tried first and did not fix them, so its changes were undone. It said:
$summary

What it changed (full diff: $state/local-fix.diff):
$stat"
    restore_snapshot "$after" ||
      local_report="$local_report
Its changes could not all be undone. The worktree as it was before is tree $snapshot."
  fi
  snapshot=""
}

if [ "$mode" = prompt ]; then
  if [ ! -s "$state/baseline-tree" ]; then
    tree=$(worktree_tree "${swift_paths[@]}") && write_state baseline-tree "$tree"
  fi
  if mv -f "$state/note" "$state/note.sending" 2>/dev/null; then
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(json_string "$(cat "$state/note.sending")")"
    rm -f "$state/note.sending"
  fi
  exit 0
fi

current=$(worktree_tree "${swift_paths[@]}") || exit 0
baseline=$(read_state baseline-tree)
if [ -n "$baseline" ] && same_swift "$baseline" "$current"; then
  write_state failed-stops 0
  exit 0
fi
given_up=$(read_state given-up-tree)
[ -n "$given_up" ] && same_swift "$given_up" "$current" && exit 0

failures=$(read_state failed-stops)
case $failures in '' | *[!0-9]*) failures=0 ;; esac
printf '%s' "$input" | grep -Eq '"stop_hook_active" *: *true' || failures=0

check_began=$(date +%s)
run_limited $((deadline - check_began)) "$state/check.out" "$state/check.out" tools/check
check_status=$?
case $check_status in
  0) passed "$current" ;;
  3) exit 0 ;; # tools/check found no xcodebuild.
  124) tell_user "tools/check did not finish within $((deadline - check_began)) seconds, so the Swift changes were not tested." ;;
esac
check_seconds=$(($(date +%s) - check_began))

failures=$((failures + 1))
report=$(failure_lines "$state/check.out")
[ -n "$report" ] || report="(tools/check printed nothing and exited with status $check_status.)"
if [ "$failures" -ge "$failure_limit" ]; then
  write_state failed-stops 0
  write_state given-up-tree "$current"
  tell_user "The unit tests still fail after $failure_limit tries, so the agent has stopped. tools/check reports:
$report"
fi
write_state failed-stops "$failures"

[ "$failures" -eq 1 ] && try_local_fix
block "The unit tests fail. tools/check reports:

$report

Fix the failures before you finish.$local_report"
