# Local fixes

When the unit tests fail at the end of a turn, `.claude/hooks/run-checks.sh` first lets a local model, served by LM Studio on `localhost:1234`, try the fix. The agent only sees the failures if that attempt doesn't fix them. This page records whether the local step is worth keeping.

Fill in the table for the first ten real failures. The hook writes one line per attempt to `local-fixes.log` in its state folder, the folder that `git rev-parse --git-path grosh-checks` prints. Each line holds the date, whether the attempt fixed the tests, the seconds it took and the first failure line. An attempt the hook skipped because too little of its 300 seconds was left shows up there too.

To turn the local step off, set `GROSH_LOCAL_FIX` to `0`. In `.claude/settings.json`, that is `"env": { "GROSH_LOCAL_FIX": "0" }` at the top level, next to `"hooks"`.

| Date | Failure | Fixed by the local model (yes or no) | Seconds taken |
| ---- | ------- | ------------------------------------ | ------------- |
