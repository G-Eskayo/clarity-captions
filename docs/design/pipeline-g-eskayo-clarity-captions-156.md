## North-star fit

Reuses the existing ADR-supersession pattern directly: a new ADR declares in its own **Status** line what it supersedes, and the superseded ADR is left as historical record rather than edited (confirmed from `docs/adr/0002` → "Partially supersedes [[0001]]", with `0001` itself untouched). CONTEXT.md's glossary addition follows the existing section-by-topic layout (`## Core concept`, `## Transcription engine`, …) and its own stated rule — domain terms only, implementation detail stays in the ADR. The Decisions block reuses the exact format already live in `docs/research/device-compatibility.md:347`.

This is the simplest sufficient approach: no new doc structure, no code, no tests to run (`swift test` is unaffected — nothing in `Packages/CaptionCore` or `Apps/Spike` changes). It spends a little extra effort going beyond the ticket's literal `grep -rni 'free' docs site` command, because that exact command misses `README.md:11` ("It is free and non-commercial by design") — found only by widening the sweep to the repo root and `docs/agents/`. Fixing it is still "about pricing," per the AC's own classification rule, so leaving it out would recreate the exact drift this ticket exists to close. It leaves the owner more in control, not less: pricing numbers and store-facing text are owner-gated, so the plan **records** facts and **flags** a real mismatch rather than silently picking a number or touching App Store Connect-bound copy.

**Real discrepancy found:** every live pricing surface (`docs/adr/0007`, `docs/app-store-listing.md`, `site/index.html`, `site/support.html`, `site/versions.html`) says **$4.99**, not $5. The issue states $5 twice, dated 2026-10-25 (more recent than the Oct 10 $4.99 decision). This isn't something to resolve by guessing — it's a Decision below.

## Verification steps (no Swift code changes, so these replace a test-first list)

This is documentation-only; `swift test --package-path Packages/CaptionCore` and the app build are unaffected by anything in this plan, so there is nothing new to unit-test. The equivalent of "tests try to break it" for a docs change is re-running the checks that could falsely report success:

1. **Repeat, not run-once:** re-run the AC's literal `grep -rni 'free' docs site` *after* edits and classify every hit (fixed vs. unrelated) in the PR body — catches an edit that silently didn't land.
2. **Scope the AC's own command undershoots:** also grep `README.md`, `CLAUDE.md`, `CONTEXT.md`, `docs/agents/*.md` for `free` — this is how `README.md:11` was found; the literal `docs site` command alone misses it.
3. **Contradictory numbers (malformed-input equivalent):** grep repo-wide for `$4.99` and `$5` after edits to confirm no new number duplicates or conflicts beyond the one flagged Decision.
4. **Dependency/link integrity:** every `[[NNNN]]` cross-reference added or edited (to `0007`, from the edited `0010` line, the new ADR's own number) resolves to a real file in `docs/adr/`.
5. **Leakage check (a person's mistake):** re-read the new CONTEXT.md term against `docs/agents/domain.md`'s rule and against the issue's "built differently on iPhone than iPad" detail — that detail must land in the ADR only, never in CONTEXT.md.
6. **Stale-state/concurrency:** immediately before creating the new ADR file, re-list `docs/adr/` to confirm the next number is still free (another worktree could claim it first).
7. **Overreach check:** re-read the edited `docs/app-review-risks.md` open question afterward to confirm it still reads as an open question (corrected premise, no invented legal/trader determination).

## Decisions

<!-- marvin:decisions -->
### price-5-vs-4-99: The issue says $5; every live pricing surface (ADR 0007, app-store-listing.md, site/index.html, site/support.html, site/versions.html) says $4.99. Which is correct?
- [ ] Record $5 in the new ADR now (most recent word from Gil); leave the live $4.99 surfaces untouched this ticket and open a follow-up ticket to bump them + App Store Connect if the $5 is real (recommended — matches this ticket's literal scope; store listing text and anything sent to Apple are owner-gated, not mine to change here)
- [ ] It's a real price bump to $5 — also update `docs/app-store-listing.md`, `site/index.html`, `site/support.html`, `site/versions.html` in this same PR, and change the live App Store Connect price afterward
- [ ] $5 in the issue was rounding/informal; record $4.99 in the new ADR instead and treat the issue text as imprecise

## Task List

1. Create `docs/adr/0026-pricing-and-live-translation-iap.md`: Status "Accepted (2026-10-25), supersedes [[0007]]'s free/non-commercial framing"; Decision = $5 one-time purchase (no subscription), live translation as a $2 IAP on iPhone and iPad (same price both, implementation differs by device — exact per-platform mechanism not yet decided, deferred to a future ADR when built); Context notes the $4.99-vs-$5 mismatch and that this plan's Decision is unresolved.
2. Add a `## Monetization` section to `CONTEXT.md` (after `## Product principles`) with a `**Live translation (IAP)**` term — domain meaning only, no implementation detail, pointing to `[[0026]]`.
3. Edit `docs/adr/0010-multi-platform-apple-expansion.md` line 18 — remove "free forever ([[0007]])" from the Constraints line, replace with a neutral pointer to the pricing ADR(s) so it no longer asserts the app is free.
4. Edit `README.md` line 11 — remove "It is free and non-commercial by design ([ADR 0007]…)"; replace with an accurate current-pricing line pointing at the new ADR (keep 0007 linked for history if natural).
5. Edit `docs/app-review-risks.md` line 142 (open question #4) — replace the "free app" premise with the actual paid, no-v1-IAP premise; keep the trader/non-trader question itself open, not answered.
6. Run both grep sweeps (the AC's literal command and the broadened one from verification step 2) and record the full hit-by-hit classification in the PR description, satisfying AC3.
7. Explicitly leave `docs/app-store-listing.md` and `site/*.html` price mentions untouched in this PR, and surface the price-mismatch Decision above instead of changing them.