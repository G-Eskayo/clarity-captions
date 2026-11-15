## North-star fit

- **Reuses before adding anything new:** the exact build/deploy split MARVIN already proved — `.github/workflows/site.yml` in `G-Eskayo/marvin` (PR #1126): a `build` job that fails closed, a `deploy` job gated on it with `concurrency: {group: pages, cancel-in-progress: false}` and `permissions: {pages: write, id-token: write}` under the `github-pages` environment. Also reuses: `.github/run-check.sh site` (the exact command `ci.yml`'s required "site" job already runs — no second implementation of the checks), the `readdirSync(dir, {recursive: true})` idiom `check-site.mjs` already uses for `Apps/` (line ~426) for the new recursive page walk, and the existing hand-made-unlisted-page convention already live in `site/for-mom-8089b966.html` (hashed name, `noindex, nofollow`, no nav link) rather than inventing a new "unlisted folder" scheme.
- **Simplest sufficient approach:** unlike MARVIN's site (Astro, built into `dist/` at CI time), this site's `site/` *is* the committed, already-verified deploy artifact — so `deploy-site.yml` needs no build step, just re-run the existing cheap check (≤5 min, `ubuntu-latest`) as its own gate, then `upload-pages-artifact`/`deploy-pages`. No `workflow_run` cross-workflow indirection (considered, rejected: adds a default-branch/`head_sha`-pinning correctness trap for no real saving, since the check it would skip costs seconds).
- **Where it spends/saves tokens-equivalent (CI minutes):** spends a second redundant run of the site check on every `main` push (cheap, already-required infra); saves a recurring human chore (the owner manually copying `main` into `gh-pages`) permanently — a one-off cost for a compounding removal of toil.
- **Leaves the user more capable, not passive:** removes a manual "remember to publish" step and a review gap (unlisted pages going straight to `gh-pages` unreviewed); the owner now reviews unlisted pages in a PR like everything else, same as before — nothing about the owner's own judgment is automated away.
- **Runs where:** GitHub-hosted `ubuntu-latest` runners (matches `ci.yml`'s `site` job) — no Mac-specific tooling needed, it's plain Node + GitHub's Pages actions.
- **Where a recorded decision applies:** none in this repo's ADRs (`docs/adr/` only covers app/engine decisions, nothing about the site's deploy mechanism) or `CONTEXT.md` (app-domain glossary only) — no conflict to flag.

## Scope found while reading the code (narrows "What to build")

- `/he/*` is **already** live, already `noindex` + draft-labelled by `build-site.mjs`'s existing `@robots`/`@draft` logic (Hebrew is `published: false` in `site-src/lang/languages.json`) — nothing to build there.
- `/beta/korea/index.html` (gh-pages only, not in git) is a one-off, still-relevant TestFlight tester page — carried over **as a real file**, same path, no redirect needed.
- `/preview/he-review/*` (gh-pages only) is a **frozen full snapshot** of the whole site taken for one family review on 2026-11-04 (8 HTML pages + their own duplicate assets/CSS/JS). Its purpose — "let family see the Hebrew draft" — is now served for real by the live `/he/` draft. Carrying the whole snapshot forward as dead weight fails north star 1; redirecting the 8 document paths to their live equivalents is the smaller, sufficient fix (nobody ever requests the snapshot's duplicate `devices.css` etc. once the HTML redirects instantly, so those don't need individual redirects).
- Extending `check-site.mjs`'s recursive page scan to the Korea tester page surfaces two real violations against the existing honest-claims rules (already enforced on every other page, including the existing unlisted `for-mom` page): "It's free in TestFlight" (bare `free`) and "within a second or two" (speed-promise pattern). These need a copy tweak, not a code exemption — the rule is already applied uniformly today.
- There is no `sitemap.xml`/`robots.txt` anywhere in `site/` today, so the AC's "no link from... the sitemap" has nothing to build against; noted, not a gap.

## Decisions

None needed. The one place the ticket names a real fork — "a fast path for urgent unlisted pages... that is a Decision for Gil" — is already resolved in the canonical (triaged) ticket text: explicitly deferred ("Left for later... this slice ships with the normal PR path only"). The other borderline call (keep each unlisted page at its existing path vs. the ticket's "one folder" phrasing) has a clear engineering answer — moving `for-mom` into a new folder would need a redirect for an already-published, already-bookmarked URL for no benefit — so it's made directly above, not put to a vote.

## Tests first

Mapped to the ticket's "How we'll try to break it" plus misuse it didn't name:

1. **A path 404s after the switch** — `check-site.mjs`: `site/beta/korea/index.html` exists and is reachable; each of the 8 old `preview/he-review/...` document paths exists in `site/` as a redirect page whose target also exists in `site/`. (New inline `check()` assertions, same style as the file's existing ones — no network crawl, no new dependency.)
2. **A broken build must leave the last good deploy up** — new `scripts/deploy-site.test.mjs` (regex/line-based YAML reading, same idiom as `ciJobs()` in `scripts/required-checks.test.mjs` — no `yaml` package, this repo takes none): `deploy` job has `needs: build`; `build` job runs `.github/run-check.sh site`.
3. **A `noindex` page leaks into nav/sitemap/language switcher** — `check-site.mjs`: every page not in the built (language) page set carries `noindex`; no built/public page's resolved `href` points at an unlisted page's path.
4. **Custom domain lost on deploy** — `scripts/build-site.test.mjs`: `buildAll()`'s `out` includes `['CNAME', 'seal-speak.gileskayo.me\n']`; `build-site.mjs --check` fails if `site/CNAME` is missing or wrong (reusing the existing staleness-check loop, no new branch).
5. **HTTPS lapsing during the switch** — not testable from code; called out as a manual post-merge verification step (task list).
6. **Two merges landing at once** — `scripts/deploy-site.test.mjs`: `deploy` job's `concurrency` is `{group: 'pages', cancel-in-progress: false}`.
7. **Misuse the ticket's list didn't name:**
   - A PR (not `main`) must never deploy → test: `deploy` job's `if` requires `github.event_name == 'push' && github.ref == 'refs/heads/main'`.
   - Wrong permissions (a compromised step escalating to write Pages) → test: top-level `permissions: contents: read`; only `deploy` has `pages: write`/`id-token: write`.
   - Supply-chain: an unpinned action rides in on a later edit → test: every `uses:` in the new workflow is pinned to a major-version tag.
   - A person forgets to run `build-site.mjs` before committing → already enforced by the existing required `--check`; unaffected, confirmed still wired.
   - Not applicable here (no outward-facing input surface — this is a build/deploy pipeline over trusted repo content, not an endpoint or form): injection/XSS/flooding-style attacks.

CaptionCore/Swift are untouched by this ticket — `swift test` stays green because nothing in `Packages/` or `Apps/` changes; not rerun as part of this work. No app UI changes, so the "Look proof" stage is not applicable — nothing new to screenshot. Everything above is `node --test`-verifiable except item 5 and the live-domain crawl, which need the owner's hands after merge (see task list) — both explicitly flagged, not assumed done.

**Complexity:** every new/changed check is a linear scan (`O(pages)`, dozens of small HTML files already read into memory by the existing pass) or a constant-time string/regex comparison (CNAME, workflow YAML lines) — no new asymptotic cost over what `check-site.mjs`/`build-site.mjs` already do.

## Task List

1. `scripts/build-site.mjs`: add `export const DOMAIN = new URL(ORIGIN).hostname`; have `buildAll()` push `['CNAME', `${DOMAIN}\n`]` into its `out` array so the existing `--check`/write logic covers it for free.
2. `scripts/build-site.test.mjs`: add tests for `DOMAIN` and the `CNAME` entry in `buildAll().out`.
3. Run `node scripts/build-site.mjs` to write `site/CNAME` (`seal-speak.gileskayo.me`), and commit it.
4. Add `site/beta/korea/index.html`: copy from `origin/gh-pages:beta/korea/index.html`, reword the two phrases that trip honest-claims (`free`, `within a second or two`), keep `noindex, nofollow`.
5. Add 8 small static redirect pages at the exact old `preview/he-review/...` paths (`index.html`, `privacy.html`, `support.html`, `versions.html`, `for-mom-8089b966.html`, and `he/index.html`, `he/privacy.html`, `he/support.html`), each `noindex, nofollow` with a `meta refresh` + visible fallback link to its live equivalent (`/he/...`, `/versions.html`, `/for-mom-8089b966.html`).
6. `scripts/check-site.mjs`: change the top-level `readdirSync(SITE)` in the `pages` list to `readdirSync(SITE, { recursive: true })` (reusing the pattern already used for `Apps/` in this same file) so nested unlisted pages get every existing check.
7. `scripts/check-site.mjs`: add the unlisted-pages check — every page outside the built (language) set carries `noindex`; no built page links to an unlisted path. Add the redirect-target check from test item 1.
8. Add `.github/workflows/deploy-site.yml`: `on: push: branches: [main]` with `paths` mirroring `required-checks.json`'s `site` check (converted to `**` globs) plus the workflow file itself; `build` job running `.github/run-check.sh site` then `actions/upload-pages-artifact@v3` on `site`; `deploy` job (`needs: build`, gated to push-to-`main`, `pages: write`/`id-token: write`, `environment: github-pages`, `concurrency: {group: pages, cancel-in-progress: false}`) running `actions/deploy-pages@v4`. Not added to `required-checks.json` (deploy-only, same as MARVIN's precedent — "the site can't break the engine").
9. Add `scripts/deploy-site.test.mjs` covering items 2, 6 and 7's structural assertions above (regex/line-based, no new dependency).
10. `.github/required-checks.json`: append `scripts/deploy-site.test.mjs` to the existing `site` check's `node --test` command list so it runs in CI.
11. Add `docs/research/evidence/2026-11-12-marvin-site-actions-deploy-proven.md` (Source: marvin#1122/PR #1126; What we took: the build/deploy split and CNAME-from-config pattern; Confidence: Ours; Drives: this ticket; Public use: Internal).
12. Cross-repo follow-up (outside this worktree, needs its own PR in `G-Eskayo/marvin`): update ADR 0080's ship step I4 line ("the Seal site: publish to gh-pages") to read the deploy result instead, and remove/retire whatever pipeline automation today performs that manual `gh-pages` publish step for this project, if any exists there.
13. Manual, owner-gated, after this PR merges to `main` and the first Actions deploy succeeds (cannot be done from this worktree — no outbound network, and it's a one-way repo-Settings change): switch the repo's Pages source from the `gh-pages` branch to "GitHub Actions"; verify HTTPS/custom domain still enforced; crawl-check the live site against today's `gh-pages` file list; only then retire the `gh-pages` branch.