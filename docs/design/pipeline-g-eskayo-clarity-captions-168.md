Now I have everything I need to write the plan.

## North-star fit

**Reuses:** The link-check logic slots into `scripts/check-site.mjs`'s existing single-pass architecture — it already loops over every built `page` (English + `site/<code>/`, via `LANGS`/`built`/`pages` from `scripts/build-site.mjs:languages/outPath`) and already reads non-HTML site files through the same `read()` helper respecting `SITE_DIR` (check #1's network-call loop over `demo.js`/`seal-data.js`/`devices.js`/etc., `scripts/check-site.mjs:49-53`). The new check reuses `read()` and `pages` verbatim and follows the file's own `macPriceProblems`/`physicalRules` pattern: an exported pure function with inline `check(...)` self-tests (`scripts/check-site.mjs:65-81`, `438-446`). No new dependency, no new file for the logic itself. The `SITE_DIR` env var (`scripts/check-site.mjs:21-22`) already exists for exactly this "seeded fault" purpose but has never actually been exercised by a test — this ticket is what finally wires it up.

**Simplicity:** Rather than trying to correctly parse arbitrary GitHub branch names (which can contain `/`, e.g. `feature/159-translation-eval`), the check only needs to *allow* two exact shapes — `main` or a 40-hex-char SHA — as the first path segment after `blob/`, `tree/`, or the raw-host's repo path. Anything else is false, full stop; no general ref-parser needed. That is the least mechanism that satisfies every attack in the ticket.

**Tokens:** Spends a small, one-time amount writing/reviewing ~25 lines of check logic + a new subprocess-based test file; saves recurring human review time forever after (a feature-branch link can no longer reach production silently). No iOS/Swift work, no screenshots — this ticket touches only `docs/` and `scripts/` + one JSON string, so the Build/App-build/Look-proof pipeline stages are not exercised.

**User capability:** This is infrastructure that protects what a visitor (including Gil's mom) sees — it makes the gap between "what we tested" and "what the site claims" fail CI instead of relying on manual review, directly serving north star 3 ("what the site promises is what she gets").

**Correction to the ticket's own text:** the triage-generated "Why" section quotes Live Translation at "$1.99 in-app purchase" — that's stale. `scripts/check-site.mjs:57-60` and ADR 0028 (updated 2026-10-30, PR #232) already fix this at **$4.99 on iPhone/iPad/Duo, $1.99 on the Mac only**. The release checklist will state the current, correct prices, not the ticket's original figure.

**What's already done / not actually broken today:** I checked every current `blob`/`raw.githubusercontent` link in `site-src/lang/en.json`, `he.json`, and the built `site/`. They all already point at `blob/main/...` — the ticket's claimed live example ("1.1's translation link points at `feature/159-translation-eval` today") is stale; that got fixed when #159/#169 merged. So this ticket is pure new guard-rail tooling, not a content fix for a currently-broken link — except for one real stale line that **is** still present: the 1.0.0 card's bullet still says "1.0.1 brings the full-screen iPad layout" (`site-src/lang/en.json:290`, built into `site/versions.html:145`). The separate 1.0.1 card (`versions.1-0-1-coming`, line 303) already correctly says "Became 1.1" / "It's part of 1.1.0" — that part was already fixed; only the stray mention inside the 1.0.0 bullet list needs removing.

## Tests to write first

1. **`badRefLinks`/`refOk` inline self-tests** (in `check-site.mjs`, matching the file's own convention, e.g. near `macPriceProblems`'s self-tests):
   - `blob/main/...` → allowed (no match).
   - `blob/feature/159-translation-eval/...` → flagged (ref captured as `feature`).
   - `tree/<40-hex-sha>/...` and `raw.githubusercontent.com/G-Eskayo/clarity-captions/<40-hex-sha>/img.png` → allowed.
   - A short SHA (7 chars) → flagged.
   - A tag-like ref (`v1.1.0`) → flagged.
   - A branch literally named `main-old` → flagged (exact-segment match, not a substring match on "main").
   - A link to a *different* repo (`github.com/FluidInference/FluidAudio`, or this repo's own `releases/latest/download/...`, which already exists in `site/for-mom-8089b966.html`) → never flagged (regex only matches `blob|tree` or the raw host's repo-pinned path).

2. **Seeded-fault integration test, new file `scripts/check-site.test.mjs`**, following the `required-checks.test.mjs` subprocess pattern (`spawnSync`/`mkdtempSync`), proving the whole script — not just the pure function — catches it:
   - Copy `site/` to a tmp dir unmodified, run `node scripts/check-site.mjs` with `SITE_DIR=<tmp>` → exit 0 (proves `blob/main/...`, already present on real pages, passes end-to-end).
   - Same copy, append a 40-char-SHA link to a page → still exit 0.
   - Copy + seed a `blob/feature/x/...` link **only into `he/index.html`** → exit 1, failure message names `he/index.html` (covers "a feature-branch link that only appears in the Hebrew page").
   - Copy + seed a bad link **only into `devices.js`**, inside a `data-` attribute string → exit 1, failure names `devices.js` (covers "only in `devices.js`" and "inside a `data-` attribute").
   - Copy + seed a bad link inside an HTML `<!-- comment -->` on a page → exit 1 (proves the check scans raw text, not the tag-stripped "visible" text used by the honest-claims checks).
   - Copy + seed three separate bad refs — a tag, a short SHA, a branch named `main-old` — all in one page → exit 1, all three reported.
   - Copy + seed a `raw.githubusercontent.com/.../feature-branch/pic.png` inside an `<img src>` → exit 1 (covers "a `raw.githubusercontent.com` image pinned to a branch").
   - Clean up every tmp dir in a `finally`.

3. **`versions.html` content regression test**: extend `build-site.test.mjs` (or rely on a `check-site.mjs` self-test) asserting the built page's 1.0.0 card text no longer matches `/1\.0\.1 brings/`, so a future edit can't silently reintroduce it. (Simplest: one `check(!/1\.0\.1 brings/.test(...))`-style assertion is lower-value than just relying on the general "verify fails when code changes without a test changing" rule — but since no existing test currently pins this bullet's exact wording, I'll add one assertion so the content fix is actually test-backed, not just eyeballed.)

No misuse case from "bad/empty/huge/malformed input, dependency failure, concurrency, wrong permissions, stale state" applies beyond the above: `check-site.mjs` has no network, no user input, and no concurrency surface — its only inputs are files already in the repo, and the attacks above are exactly the adversarial-input space the ticket itself specifies.

## Decisions

None. Every open question above (raw-host scope, exact-segment "main" matching, where the 1.0.1 fix goes) has one clearly correct answer given the existing code and ADR 0028, not a design tradeoff for the owner to pick between.

## Task List

1. **`site-src/lang/en.json`**: fix `versions.live-captions-of-what` (line 290) — drop "`; 1.0.1 brings the full-screen iPad layout`", keeping "...on your iPhone. It also runs on iPad, in the iPhone-sized layout."
2. Rebuild the site: `node scripts/build-site.mjs` (regenerates `site/versions.html` from the fixed source).
3. **`scripts/check-site.mjs`**: add `export const refOk = (ref) => ...` and `export function badRefLinks(text) { ... }` (regex over raw file text, scoped to `github.com/G-Eskayo/clarity-captions/(blob|tree)/<ref>` and `raw.githubusercontent.com/G-Eskayo/clarity-captions/<ref>`), with inline self-tests next to the function definition.
4. In the same file, add a new numbered check section looping `for (const f of [...pages, 'seal-data.js', 'devices.js'])` calling `badRefLinks(read(f))` and `check(false, ...)` for every hit, naming the file and the offending URL.
5. Add a content-regression self-test (or extend `build-site.test.mjs`) asserting the built 1.0.0 card no longer contains "1.0.1 brings".
6. **New file `scripts/check-site.test.mjs`**: the seeded-fault `SITE_DIR` integration tests listed above (copy real `site/` to a tmp dir per test, seed, spawn `node scripts/check-site.mjs`, assert exit code + message, clean up).
7. **`.github/required-checks.json`**: add `scripts/check-site.test.mjs` to the `site` check's first `node --test ...` group so it runs in CI and the merge gate (no change to `ci.yml` job names needed — `required-checks.test.mjs`'s drift check only checks job names/`run-check.sh` invocation, not the command body).
8. **New file `docs/release-checklist.md`**: a reusable checklist (ticked or marked N/A-with-reason per use) covering: the Versions card matches exactly what ships / status badge matches App Store Connect / only tested+switched-on caption languages / prices match App Store Connect (current correct figures: $4.99 app, Live Translation $4.99 iOS + $1.99 Mac, ADR 0028); every number on the site traced to a `docs/perf/` final report; home/support page device requirements and features match the release; App Store listing text matches the site. Note inline that `scripts/check-site.mjs` already enforces the non-main-link rule automatically, so that line is a sanity check, not manual re-verification.
9. Verify: `swift test --package-path Packages/CaptionCore` (unaffected, confirms no regression), `node --test scripts/build-site.test.mjs scripts/lang-offer.test.mjs scripts/required-checks.test.mjs scripts/check-site.test.mjs`, `node scripts/build-site.mjs --check`, `node scripts/check-site.mjs`, `node --test scripts/check-evidence.test.mjs`, `node scripts/check-evidence.mjs` — i.e. the exact `site` check command end to end.
10. In the PR description: state plainly that the acceptance criterion "1.1.0's release PR links [the checklist]" can't be satisfied by this PR (1.1.0 hasn't shipped yet, per the Versions page's own "Coming next" status) — the document is created and ready to link when that release PR happens. Also state plainly: no iOS/Swift files change, no UI change, so no screenshots are produced or needed for this PR.