## North-star fit

- **Reuses before adding anything new:**
  - `scripts/check-evidence.mjs`'s `problems(dir)` pattern (pure function, unit-tested directly) and `scripts/required-checks.test.mjs`'s `spawnSync`-against-a-seeded-temp-copy pattern — the new seeded-fault test for the branch-link check follows this exact shape instead of inventing a new test style.
  - `scripts/check-site.mjs`'s own established self-test convention: every exported helper (`macPriceProblems`, `physicalRules`, `ratio`, …) gets inline `check(...)` self-tests right after its definition. The new `branchLinkProblems` helper follows that.
  - The `pages` array and `read()` helper already built in `scripts/check-site.mjs` (lines 30–34) already enumerate every built page in every language plus hand-made pages — the new check reuses that enumeration instead of writing its own.
  - `SITE_DIR` (`scripts/check-site.mjs:22`) already exists as a hook for exactly this ("checks a copy of site/, used to prove the checks catch seeded faults") but nothing exercises it today — this ticket is the first to actually use it in an automated test.
- **Simplest sufficient approach:** GitHub never lets a ref literally be `main` or a 40-hex-char SHA *and* contain a `/`, so classifying by the **first path segment alone** after `blob/`, `tree/`, or the raw-host repo path is enough — no need to parse multi-segment branch names (e.g. `feature/159-translation-eval`) or know the real branch list. `segment === 'main' || /^[0-9a-f]{40}$/i.test(segment)` is the whole rule.
- **Token/compute cost:** a pure regex/string-equality check added to a Node script that already runs in ~seconds in the existing `site` CI job (5 min timeout); no network calls, no new dependency. Cheap once, and it then holds the invariant on every future PR for free.
- **Phone-OS fit:** neutral — a release-integrity guard, not phone-OS-shaped work either way.
- **Human-experience fit (north star 3):** directly serves "what the site promises is what she gets" — removes a manual, easy-to-forget audit step and replaces it with a check that fails the build, so a stale feature-branch link (which could silently 404 or drift after that branch is deleted) can't ship unnoticed.

One scope correction to the ticket's own wording: the "Why" section's acceptance criterion says the checklist should be "ticked for 1.1.0" — but the Task/Purpose line clarifies this means **ticked in 1.1.0's release PR**, not inside `docs/release-checklist.md` itself. 1.1.0 hasn't shipped (App Store Connect status, final language sign-off, and pricing there aren't things this agent can see), so `docs/release-checklist.md` will be a reusable, version-agnostic checklist (copy it into each release PR's description and tick there), not a doc pre-filled with 1.1.0's state. That's consistent with how `site/versions.html` itself already treats 1.1.0 as "Coming next" and not yet live.

## Tests first

In `scripts/check-site.mjs` (inline self-tests, same style as the existing ones):
1. `.../blob/main/docs/...` → no problem.
2. `.../blob/<40-hex-char SHA>/docs/...` → no problem.
3. `.../blob/feature/159-translation-eval/docs/...` (a real branch name with a slash in it) → caught.
4. `.../blob/v1.2/docs/...` (a tag) → caught.
5. `.../tree/main-old/...` (a branch literally named `main-old`) → caught, not mistaken for `main`.
6. `.../blob/abc123/...` (a short SHA) → caught.
7. A 41-char and a 39-char hex string → both caught (only an exact 40-char SHA is allowed).
8. `raw.githubusercontent.com/G-Eskayo/clarity-captions/<branch>/assets/x.png` (an image link) → caught the same as `blob`/`tree`.
9. `.../blob/Main/...` (capitalized) → caught; branches are case-sensitive.
10. A `github.com/<other-org>/<other-repo>/blob/some-branch/...` link → left alone (no false positive on unrelated repos).

New `scripts/check-site.test.mjs` (seeded-fault integration tests via `SITE_DIR`, `spawnSync`, copying the real built `site/` to a temp dir — the misuse cases from "How we'll try to break it"):
11. A feature-branch link seeded **only** into the copied `site/he/index.html` → `check-site.mjs` exits non-zero and names that file.
12. A feature-branch link seeded **only** into the copied `devices.js` → exits non-zero and names it.
13. A bad link seeded inside an HTML comment, and another inside a `data-` attribute → both still caught (proves the scan reads raw text, not just `href`/`src` attributes the way section 4's link-existence check does).
14. A `raw.githubusercontent.com` image pinned to a branch (not a SHA) → caught.
15. The real, unmodified copy of `site/` → passes with zero branch-link failures (today's site already only links to `main`, confirmed by inspection).
16. A copy with an added `blob/main/...` link and a 40-char-SHA `raw.githubusercontent.com` image, seeded into a harmless spot → still passes (no false failure).

Regression test for the stale-line fix, added to `scripts/build-site.test.mjs`:
17. `strings('en')['versions.live-captions-of-what']` no longer contains the string `1.0.1` — so a future edit can't silently reintroduce the "1.0.1 brings…" claim without a test changing.

## Task List

1. In `scripts/check-site.mjs`: add a `BRANCH_LINK` regex and an exported `branchLinkProblems(text)` helper (first-path-segment rule above), with inline self-tests (items 1–10).
2. In `scripts/check-site.mjs`: add a new check section that runs `branchLinkProblems` over every entry in the existing `pages` array (all languages) plus `site/seal-data.js` and `site/devices.js`, pushing one failure per bad ref naming the file and the ref.
3. Add `scripts/check-site.test.mjs` with the seeded-fault tests (items 11–16), using `mkdtempSync`/copy-then-edit of real `site/` and `spawnSync('node', ['scripts/check-site.mjs'], { env: { SITE_DIR: tmp } })`.
4. Add `scripts/check-site.test.mjs` to the `site` check's command array in `.github/required-checks.json` (alongside `build-site.test.mjs`, `lang-offer.test.mjs`, `required-checks.test.mjs`) so the existing CI `site` job runs it — no change to `ci.yml` needed.
5. Fix the stale line: edit `site-src/lang/en.json`'s `versions.live-captions-of-what` key to stop saying "1.0.1 brings the full-screen iPad layout" (reword to point at 1.1, matching the existing `versions.not-on-the-app` card's own "It's part of 1.1.0" wording).
6. Add the regression test (item 17) to `scripts/build-site.test.mjs`.
7. Rebuild the site (`node scripts/build-site.mjs`) to regenerate `site/versions.html` from the fixed source and commit the output alongside the source change.
8. Write `docs/release-checklist.md`: a reusable, version-agnostic checklist covering the Versions card (contents, status badge, tested/switched-on languages only, price — pointing at `PRICES` in `scripts/check-site.mjs` as the source of truth rather than restating numbers that could drift), every number traced to `docs/perf/`, source links (note this is enforced automatically by the new `check-site.mjs` check — confirm CI's `site` job is green), home/support page parity, and App Store listing parity; with a short usage note that each release's PR copies this list into its description and ticks it there.
9. Run `node scripts/build-site.mjs --check`, `node scripts/check-site.mjs`, and the full `node --test scripts/*.test.mjs` suite locally to confirm everything is green before opening the PR.
10. Attempt a screenshot of the corrected 1.0.0 card via `scripts/check-site-versions.mjs`'s existing mechanism for the PR; if Chrome/`playwright-core` isn't available in this environment, say so plainly in the PR instead of claiming a screenshot was captured.