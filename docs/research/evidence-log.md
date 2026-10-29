# Evidence log: the research behind Seal's decisions

One entry per source. Each says what we took from it, how strong it is, and which decision it drives, so the
portfolio page and the marketing site (#44) can show the reasoning, not just the result. **Add an entry whenever
research informs a decision**, and link the ADR, PR or ticket it drove.

Confidence: **Strong** (controlled study or official documentation), **Moderate** (guideline or several consistent
sources), **Weak** (single small study, secondary report or anecdote), **Ours** (our own measurement).

Public use: **Yes** (fine to cite on the portfolio or marketing pages as written), **Careful** (cite with its
caveat), **Internal** (process detail, not for marketing).

## Where the entries are

Every entry is its own file in [`evidence/`](evidence/) (#210), so branches that add evidence at the same time never
edit the same lines or pick the same number.

- **E1–E29** keep the numbers they're cited by: `evidence/E07-building-on-existing-on-device-speech.md` is "E7".
- **New entries** are `evidence/YYYY-MM-DD-<slug>.md`, starting with a plain `# Title` and the five fields:
  **Source** (or **Sources**), **What we took**, **Confidence**, **Drives**, **Public use**. Cite one by its
  file name, e.g. "evidence `2026-10-29-hebrew-normaliser`".
- `node scripts/check-evidence.mjs` checks every entry (CI runs it). `node scripts/check-evidence.mjs --print`
  prints the whole log as one page, for the portfolio and the marketing site.
