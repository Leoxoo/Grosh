## Architecture and performance

Every user has **the 16k store** (~16,000 transactions). Before writing or reviewing code that reads transactions, adds a computed property to a model, adds a screen or `@Query`, or touches balances, lists or reports, read `docs/agents/architecture.md`: where each component lives, where a screen gets its data, and the performance rules.

## Tests and checks

The Stop hook (`.claude/hooks/run-checks.sh`) runs the unit tests after an agent edits Swift, so a failure comes back to the agent without a manual run. Run them with `tools/check`, or `tools/check --ui` for the UI tests. See `docs/agents/testing.md`, `docs/agents/benchmarks.md`, `docs/agents/log-check.md`, `docs/agents/ui-smoke.md` and `docs/agents/local-fixes.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
