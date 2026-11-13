#!/usr/bin/env bash
#
# Checks .claude/hooks/block-dangerous-git.sh: each case hands it a Bash call the way Claude Code does and checks that
# it blocks the call (exit 2, with a reason on stderr) or lets it through (exit 0, silent).
#
#   tools/tests/block-dangerous-git/run.sh

set -u

here=$(cd "$(dirname "$0")" && pwd -P)
hook=$(cd "$here/../../.." && pwd -P)/.claude/hooks/block-dangerous-git.sh

passed=0
failed=0

# check <blocks|passes> <command>: runs the hook on a Bash call of that command.
check() {
    local expected=$1 command=$2 input err status
    input=$(printf '{"session_id":"test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"}}' "$command")
    err=$(printf '%s' "$input" | "$hook" 2>&1 >/dev/null)
    status=$?
    if { [ "$expected" = blocks ] && [ "$status" = 2 ] && printf '%s' "$err" | grep -q '^BLOCKED'; } ||
        { [ "$expected" = passes ] && [ "$status" = 0 ] && [ -z "$err" ]; }; then
        passed=$((passed + 1))
        echo "ok   $expected: $command"
    else
        failed=$((failed + 1))
        echo "FAIL $expected: $command (exited $status${err:+, said: $err})"
    fi
}

check blocks 'git push --force origin main'
check blocks 'git push -f'
check blocks 'git push -f origin main'
check blocks 'git push --mirror'
check blocks 'git push origin --delete feature'
check blocks 'git push origin :feature'
check blocks 'git push origin +main'
check blocks 'git reset --hard HEAD~1'
check blocks 'git clean -f'
check blocks 'git clean -fd'
check blocks 'git clean -df'
check blocks 'git clean -xfd'
check blocks 'git clean --force'
check blocks 'git branch -D old'
check blocks 'git checkout .'
check blocks 'git checkout -- .'
check blocks 'git restore .'
check blocks 'git restore --staged --worktree .'
check blocks 'cd repo && git reset --hard'

check passes 'git push'
check passes 'git push -u origin feature'
check passes 'git push origin feature-fix'
check passes 'git status --short'
check passes 'git clean -n'
check passes 'git branch -d merged'
check passes 'git checkout main'
check passes 'git checkout -- Grosh/App.swift'
check passes 'git restore Grosh/App.swift'
check passes 'git reset --soft HEAD~1'
check passes 'ls -la'

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
