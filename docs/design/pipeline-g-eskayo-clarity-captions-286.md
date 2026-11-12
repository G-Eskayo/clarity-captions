## North-star fit

- **Reuses before adding:** the required-checks framework itself (`.github/required-checks.json` + `.github/run-check.sh` + `scripts/required-checks.test.mjs`, marvin#826) — every other repo check (`caption-core`, `spike-app`, `mac-app`, `site`) already follows this "one id, one CI job, one `run-check.sh` call" shape, and `site`'s command chain (`node --test ...; node ...mjs`) is the existing pattern for a Node-only static check. `EngineEval`'s and `SystemReplay`'s `Package.swift` already show the correct syntax (`exact: "0.17.5"`) and `SystemReplay/Package.swift`'s own comment already names this exact gap — that comment becomes stale once this ships and should be trimmed.
- **Simplest sufficient approach:** one shared Node script (`scripts/check-fluidaudio-pin.mjs`) does the version-string/consistency logic once; it's called twice — once as its own cheap static CI check, once (with a path argument) from inside the two app-build checks that already run `xcodebuild` — rather than writing the comparison logic twice or standing up a fourth macOS job.
- **Token/compute cost:** the static half (regex over `Package.swift`, JSON diff over `Package.resolved`) needs no Xcode and runs on `ubuntu-latest` in seconds, like `site`. The "what does the app actually resolve" half needs `xcodebuild -resolvePackageDependencies`, which is cheap next to the build that already happens in `spike-app`/`mac-app` (a resolve-only step, not a second build), so it piggybacks on jobs that already run rather than adding a new 30–40 minute macOS job — see Decision 1 below, since this trades a small coupling cost for a meaningfully smaller CI bill.
- **Human experience:** closes the exact gap #273's replay found — a build's accuracy becomes reproducible from its commit, and a silent dependency bump can no longer explain an accuracy change nobody reviewed. The owner stays in control of engine upgrades (their own PR, scored by the replay) rather than losing visibility to a background resolver.

## Files already read

`Packages/CaptionCore/Package.swift`, `Packages/EngineEval/Package.swift`, `Packages/SystemReplay/Package.swift`, their three `Package.resolved`, `.github/workflows/ci.yml`, `.github/required-checks.json`, `.github/run-check.sh`, `scripts/required-checks.test.mjs`, `NOTICE.md`, `Apps/Spike/project.yml`, `Apps/Mac/project.yml`, `docs/adr/0025-parakeet-ultra-caption-engine.md`, `CONTEXT.md` (FluidAudio entry, line 44).

Confirmed: `CaptionCore/Package.swift:15` is the only `from:` requirement; `EngineEval` and `SystemReplay` already use `exact: "0.17.5"` and all three `Package.resolved` already pin revision `0b1f462…` / version `0.17.5`. Neither `Apps/Spike/CaptionSpike.xcodeproj` nor `Apps/Mac/CaptionMac.xcodeproj` (both gitignored, already generated in this worktree) has a `swiftpm/Package.resolved` yet — confirming AC3 genuinely needs an explicit resolve step, not just reading a committed file.

## Decisions

<!-- marvin:decisions -->
### ci-job-shape: Where should the "app build actually resolves the pin" check (AC3) run?
- [ ] Append a resolve-and-check step to the existing `spike-app` and `mac-app` required checks, right after their `xcodebuild ... build` succeeds (reuses their macOS runner and `paths` gating; couples an unrelated concern into those jobs' failure output)
- [ ] Give it a separate new required check/job (e.g. `fluidaudio-app-resolve`) that only runs `xcodegen generate && xcodebuild -resolvePackageDependencies` for both apps (clean failure attribution and its own `paths`; a fourth macOS job, though resolve-only so much cheaper than a full build)

## Tests to write first

All in `scripts/check-fluidaudio-pin.test.mjs`, following `scripts/required-checks.test.mjs`'s style (`mkdtempSync` fixture dirs, no mocks — the script always reads real files it's pointed at):

1. **`from:` requirement** on the FluidAudio dependency line → check fails, names the offending `Package.swift`.
2. **`upToNextMinor:` requirement** → fails.
3. **`branch:` requirement** → fails.
4. **`exact:` with a different version/revision in one package than the others** (seeded cross-package mismatch) → fails, names both packages and both values.
5. **`Package.resolved` left at an old revision while `Package.swift`'s `exact:` moved on** → fails (catches the "a sibling file lags" case explicitly called out in the ticket).
6. **A simulated app-resolved `Package.resolved`** (the `--app-resolved <path>` argument) that names a different FluidAudio version than the committed pin → fails; this is the regression test standing in for "the xcodegen-generated project resolves on its own" since a real `xcodebuild -resolvePackageDependencies` run isn't exercisable inside a Node unit test.
7. **Everything pinned and consistent** (today's real repo state, after the `Package.swift` fix below) → passes, including when an `--app-resolved` file matching the pin is passed.
8. **Failure message content:** every failing case's combined output includes the sentence that a FluidAudio bump needs its own PR scored by the #273 replay (AC4) — asserted once per distinct failure path, not just the happy path.
9. **Misuse the ticket's list missed:**
   - Malformed/truncated `Package.resolved` (not valid JSON, or missing the `fluidaudio` pin entry entirely) → fails closed with a clear message, not a crash or a false pass.
   - No `Package.swift` in the repo declares FluidAudio at all (hypothetical future refactor) → the check has nothing to enforce and passes trivially (documented, not silently wrong).
   - A transitive dependency's own `Package.resolved` (e.g. `EngineEval`'s `argmax-oss-swift` pin) differing in FluidAudio version from the app's pin → **does not fail** the check, but is printed as a noted line (AC's "noted in the report even if not pinned here").
   - Two packages' FluidAudio `exact:` values match but their `Package.resolved` revisions differ for the same version string (a corrupted resolve) → fails.
10. **`required-checks.test.mjs`'s existing tests** must keep passing unchanged (drift test between `ci.yml` and `required-checks.json`) once the new check/job is added — run as a sanity check, not a new test, after the wiring step.
11. **`swift test --package-path Packages/CaptionCore`** still green after the `Package.swift` edit (the pin is unchanged, only the requirement operator changes, so no source changes are expected — this is a regression guard, not new coverage).

**Untested by this plan, left to the pipeline's own build/screenshot stage:** a real `xcodebuild -resolvePackageDependencies` run against the generated `Apps/Spike`/`Apps/Mac` projects is exercised only in CI (macOS runner with Xcode); it cannot run inside this session's Node test process. No UI changes are involved, so no screenshots are needed for this ticket.

## Task List

1. Decide `ci-job-shape` (owner, via the Decision above) — proceed with "append to existing jobs" as the default if unanswered, since it's cheaper and reversible later.
2. Write `scripts/check-fluidaudio-pin.test.mjs` with tests 1–9 above (red).
3. Write `scripts/check-fluidaudio-pin.mjs`: globs `Packages/*/Package.swift`, extracts the FluidAudio dependency requirement and version, cross-checks against sibling `Package.resolved` files and against each other, optionally checks a `--app-resolved <path>` file, notes (non-failing) transitive drift, and ends any failure's output with the #273-replay sentence (AC4) (green).
4. Edit `Packages/CaptionCore/Package.swift:15`: `from: "0.17.5"` → `exact: "0.17.5"` (AC1).
5. Trim the now-stale "gap" comment in `Packages/SystemReplay/Package.swift` (lines 19–21) and `Packages/EngineEval/Package.swift` (line 17), since the gap they describe is closed.
6. Add the `fluidaudio-pin` entry to `.github/required-checks.json` (`cwd: "."`, `command: ["node", "scripts/check-fluidaudio-pin.mjs"]`, `paths: ["Packages/*", "scripts/check-fluidaudio-pin*"]`) and a matching job in `.github/workflows/ci.yml` (ubuntu-latest + Node 22, like `site`).
7. Per the `ci-job-shape` decision, wire AC3: either extend `spike-app`'s and `mac-app`'s `command` in `required-checks.json` with a post-build `xcodebuild -resolvePackageDependencies` + `node scripts/check-fluidaudio-pin.mjs --app-resolved <path>` call, or add the separate `fluidaudio-app-resolve` check/job and its `.yml` entry.
8. Add one line to `NOTICE.md`'s FluidAudio section stating the shipped version is the one pinned in the commit (AC's "say so in NOTICE.md").
9. Run `swift test --package-path Packages/CaptionCore`, `node --test scripts/check-fluidaudio-pin.test.mjs`, and `node --test scripts/required-checks.test.mjs` locally; confirm all pass.
10. Open the PR naming #286, stating plainly that the AC3 app-resolve step is verified by the pipeline's own CI run, not locally in this session.