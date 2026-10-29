# Clarity Captions — Repo Instructions

## Agent skills

### Issue tracker

GitHub Issues on `G-Eskayo/clarity-captions`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles, all real labels on this repo with default naming (no overrides).
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Pull requests

Anything that changes how the app looks must include screenshots of the real running app, or say plainly that none could be captured. See `docs/agents/pr-requirements.md`.

### Research behind decisions

When research informs a decision (a study, guideline, Apple doc or our own measurement), add a new file
`docs/research/evidence/YYYY-MM-DD-<slug>.md` (never a number, never an edit to `evidence-log.md`): a `# Title`, then
source link, what we took, confidence, the decision it drives, and whether it can be cited publicly. Rules and the
checker are in `docs/research/evidence-log.md`. The portfolio page and the marketing site draw from it.
