## North-star fit

- **Reuses:** `scripts/check-site.mjs`'s own established pattern end-to-end — the `pages` array (every language's built HTML, already assembled from `languages()` + `readdirSync(SITE)`), the `read()` helper (already `SITE_DIR`-aware, see line 22/34), the `check(ok, msg)` accumulator, and the file's convention of an inline `check(fn(...) === want, 'self-test')` next to every exported helper (`macPriceProblems`, `physicalRules`, etc.). The new branch-link rule is one more section in that same file, not a new mechanism. For the seeded-fault test, I reuse `scripts/required-checks.test.mjs`'s pattern of `spawnSync`-ing the real script against a temp directory rather than importing it (importing is unsafe here: `check-site.mjs` runs its checks at import time and calls `process.exit(1)` on failure).
- **Simplest sufficient approach:** a single regex (`github.com/G-Eskayo/clarity-captions/(blob|tree)/<ref>` or `raw.githubusercontent.com/<owner>/<repo>/<ref>`) run over raw file text (not HTML-tag-parsed), so it catches a link no matter whether it sits in an `href`, a comment, or a `data-` attribute for free — no separate comment/attribute-parsing logic needed. Validity is one equality check: the first path segment after the ref position must be exactly `main` or a 40-hex-char SHA; anything else (a tag, a short SHA, `main-old`, or a slash-containing branch like `feature/159-translation-eval`, whose first segment is `feature`) fails that equality and is correctly rejected without needing to special-case slash-containing branch names.
- **Where it spends tokens:** one new ~15-line section in an already-loaded file, plus one new test file following an existing template almost verbatim — no new scripts, no new dependencies.
- **Correction to the ticket:** the triage-generated checklist text still quotes the pre-#228 price ("$1.99 in-app purchase" for Live Translation). The real, current prices are `PRICES = { app: '4.99', translationIOS: '4.99', translationMac: '1.99' }` (`scripts/check-site.mjs:60`, already enforced on every page). `docs/release-checklist.md` will state the current prices, not the stale ones from the ticket body.
- **Current state check:** I checked every page in `site/` and `site-src/`; none currently contains a non-`main` GitHub source link — the "`feature/159-translation-eval`" example in the ticket's "Why" section is already stale (the links are all `.../blob/main/...` today). So this ticket is adding the *guard*, not fixing a live violation, except for the one real stale line acceptance criteria #4 names (the 1.0.0 card's "1.0.1 brings the full-screen iPad layout").
- **1.1.0's release PR:** 1.1.0 is still `"Coming next"` (`site-src/lang/en.json:521`); its release PR doesn't exist yet (PR #267 was a TestFlight-only build, not an App Review submission). So acceptance criterion 1 ("1.1.0's release PR links it, ticked") can't be completed by this PR — I'll create the checklist so it's ready to paste into that future PR, and say so plainly rather than inventing a PR that doesn't exist.
- **More capable, not more passive:** this stops a cut feature or a feature-branch link silently going live (the stated purpose) while leaving the human judgment calls (status badges matching App Store Connect, which languages are "tested and switched on") to Gil in the checklist — the script only catches the one objectively-checkable failure mode (link drift).
- **Untested behavior:** none of this touches `Apps/` or `Packages/CaptionCore`, so `swift test` and the app-build/look-proof playbook stages are not applicable — there is no UI or app behavior to screenshot. Everything here is covered by `node --test` and `node scripts/check-site.mjs`, which I can run myself.

## Tests first

All in `scripts/check-site.mjs` (inline self-tests, run every time the script runs) and a new `scripts/check-site.test.mjs` (seeded-fault process tests), covering the ticket's "How we'll try to break it" and "Attacks" lists plus the misuse cases the section didn't name:

1. **Inline self-tests on the pure helpers** (`badRef`, `REF_LINK`), matching the file's existing convention:
   - `badRef('main')` and `badRef('a'.repeat(40))` → allowed (false).
   - `badRef('feature')`, `badRef('main-old')`, `badRef('v1.0.0')`, `badRef('a1b2c3d')` (short SHA) → rejected (true).
   - `REF_LINK` extracts `feature` (not the whole branch) from a `blob/feature/159-translation-eval/...` URL — proves the slash-containing-branch case is still caught even though only the first segment is captured.
   - `REF_LINK` matches inside an HTML comment and inside a `data-` attribute (pure string match, no tag parsing).
2. **Seeded-fault process tests** (`check-site.test.mjs`, one real copy of `site/` mutated per case, run through the actual CLI via `spawnSync('node', ['scripts/check-site.mjs'], { env: { SITE_DIR } })`):
   - Baseline: an unmodified copy of `site/` passes (status 0) — proves the copy mechanism itself isn't the thing making other cases fail.
   - A feature-branch link seeded **only into `he/index.html`** → fails, message names that file (not just the English page).
   - A feature-branch link seeded **only into `devices.js`** → fails, message names `devices.js`.
   - A link to a **tag** (`v1.0.0`) → fails.
   - A link to a **short SHA** (7 chars) → fails.
   - A link to a branch literally named **`main-old`** → fails.
   - A link **inside an HTML comment** → fails.
   - A link **inside a `data-` attribute** → fails.
   - A **`raw.githubusercontent.com`** image pinned to a branch → fails.
   - A link pinned to a **full 40-char SHA** and a plain `.../blob/main/...` link → both pass (the check doesn't over-trigger on the two allowed forms).
3. Existing `build-site.test.mjs` / `check-evidence.test.mjs` / `required-checks.test.mjs` are unchanged and keep passing — proves nothing else regressed.
4. Manual verification I can run myself: `node --test scripts/build-site.test.mjs scripts/lang-offer.test.mjs scripts/required-checks.test.mjs scripts/check-site.test.mjs && node scripts/build-site.mjs --check && node scripts/check-site.mjs && node --test scripts/check-evidence.test.mjs && node scripts/check-evidence.mjs` — the exact CI `site` job command, with the new test file added.

No Decisions section — the ticket is concrete enough that every open question (price figures, scope of files scanned, SHA-length rule, checklist location) resolves from the code or the ticket text itself without a real either/or choice for Gil to make.

## Task List

1. [ ] `scripts/check-site.mjs`: add `REF_LINK` regex and `badRef(ref)` helper (exported, with inline self-tests) that flags any `github.com/G-Eskayo/clarity-captions/(blob|tree)/<ref>` or `raw.githubusercontent.com/<owner>/<repo>/<ref>` whose ref isn't exactly `main` or a 40-hex-char SHA.
2. [ ] In the same file, scan every entry in `pages` and the existing JS-file loop (`demo.js`, `seal-data.js`, `motion.js`, `devices.js`, `lang.js`) for `REF_LINK` matches via `read()`, calling `check(!badRef(ref), ...)` with a message naming the file and the bad ref.
3. [ ] Add `scripts/check-site.test.mjs`: seeded-fault tests against a `cpSync`-copied `site/`, covering the 9 cases above (baseline pass, Hebrew-only link, devices.js-only link, tag, short SHA, `main-old`, HTML-comment link, data-attribute link, raw.githubusercontent-on-a-branch, and the two allowed forms).
4. [ ] `.github/required-checks.json`: add `scripts/check-site.test.mjs` to the `site` check's `node --test` command list, so CI exercises the seeded-fault proof, not just the inline self-tests.
5. [ ] `site-src/lang/en.json`: fix `versions.live-captions-of-what` — drop the dangling "1.0.1 brings the full-screen iPad layout" clause (the feature is already described in 1.1.0's own card); no Hebrew change needed (`he.json` has no `versions.*` strings — Hebrew doesn't publish `versions.html`).
6. [ ] Rebuild: `node scripts/build-site.mjs`, and confirm `node scripts/build-site.mjs --check` is clean.
7. [ ] Write `docs/release-checklist.md`: the pre-App-Review checklist from "What to build" (Versions card content/status/languages/price, every number traced to `docs/perf/`, source links on `main`, home/support page parity, App Store listing text parity), using the current prices ($4.99 app once; Live Translation $4.99 iPhone/iPad/Duo, $1.99 Mac) rather than the ticket's stale figures, and a note that it's pasted into each release PR and ticked (or marked N/A with a reason) there — flagging that 1.1.0's own release PR doesn't exist yet (1.1.0 is still "Coming next"), so that part of acceptance criterion 1 is deferred to when that PR opens.
8. [ ] Run the full `site` CI command locally to verify everything is green.