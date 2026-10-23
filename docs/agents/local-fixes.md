# Local fixes

When the unit tests fail at the end of a turn, `.claude/hooks/run-checks.sh` first lets a local model, served by LM Studio on `localhost:1234`, try the fix. The agent only sees the failures if that attempt doesn't fix them. This page records whether the local step is worth keeping.

The local step runs only when `GROSH_LOCAL_FIX_MODEL` holds the id of the model LM Studio serves. Set it under `"env"` in `.claude/settings.local.json`, which is personal and not committed:

```json
{ "env": { "GROSH_LOCAL_FIX_MODEL": "<the model id LM Studio serves>" } }
```

To turn the local step off, set `GROSH_LOCAL_FIX` to `0`. In `.claude/settings.json`, that is `"env": { "GROSH_LOCAL_FIX": "0" }` at the top level, next to `"hooks"`.

The Stop hook has 300 seconds in all, so the local attempt gets only what is left after the first `tools/check` run. With runs of 1 to 3 minutes it is often skipped, and the log shows when. A hook timeout of 600 seconds would give it its full five minutes.

A failed attempt undoes every change made in the worktree since the snapshot, including the developer's own edits, so don't edit the worktree while the hook runs.

Fill in the table for the first ten real failures. The hook writes one line per attempt to `local-fixes.log` in its state folder, the folder that `git rev-parse --git-path grosh-checks` prints. Each line holds the date, whether the attempt fixed the tests, the seconds it took and the first failure line. Skipped attempts are there too, with the reason.

| Date | Failure | Fixed by the local model (yes or no) | Seconds taken |
| ---- | ------- | ------------------------------------ | ------------- |
