## North-star fit

**Reuses before adding anything new:**
- `scripts/system-replay/at-build.sh:33-44` already parses a FluidAudio pin out of a `Package.resolved`-shaped JSON file with a tiny `python3 -I` snippet that handles both pin-file shapes (`{"pins":[...]}` with key `identity`, and the older `{"object":{"pins":[...]}}` with key `package`) — this is lifted verbatim into the new checker rather than rewritten, and the same dual-shape handling means it will also read Xcode's `workspace-state.json` (same pin shape) with no extra branch.
- `scripts/required-checks.test.mjs` already establishes the pattern for testing a shell script from Node: `mkdtempSync`, write fixture files, `spawnSync` the script, assert on exit code/stdout. The new checker's test file follows this exactly instead of inventing a different test style.
- `.github/required-checks.json` / `.github/run-check.sh` / `.github/workflows/ci.yml` is the one existing mechanism for "a CI check that the gate and GitHub Actions both run" (marvin#826) — this ticket adds one more entry and one more job to that list, it doesn't invent a second CI mechanism.
- `docs/perf/whole-system-replay-design.md:56-61` already documents this exact failure mode (CaptionCore's `from:` resolving 0.18.3 unexpectedly, and the fact that the laptop's own DerivedData was where the real resolved version was found) — that paragraph is the evidence for where the app's "actual resolved version" check must look, and gets corrected once CI enforces this.

**Simplest sufficient approach:** one small bash+python3 script (`scripts/check-fluidaudio-pin.sh`) doing two things — (1) a static, repo-wide check that every `Package.swift` touching FluidAudio uses `exact:` and that every package's resolved pin agrees, runnable on `ubuntu-latest` with no Xcode; (2) an optional app-side check, invoked with a discovered DerivedData pin file, that the same script's logic is reused for. No new abstraction layer, no new language/toolchain in CI (bash, python3, jq are already required by `run-check.sh`'s own doc comment).

**Where it saves/spends:** the static half runs on `ubuntu-latest` with no setup step (cheaper than the existing Node-based `site` job) — spends nothing extra. The dynamic half spends zero extra CI minutes: it rides inside the `spike-app`/`mac-app` jobs' existing `xcodebuild … build` invocation (which already resolves packages and already needs the 740 MB of bundled models fetched), rather than standing up a dedicated resolve-only job that would have to pay that same model-fetch cost again just to make `xcodegen generate` succeed.

**Capability, not passivity:** this removes a silent-drift failure mode a human can't see from the diff (a dependency bump changing accuracy with no PR to review) and makes it a loud, named CI failure instead — strictly reduces what can go wrong unnoticed, doesn't remove any judgment call from Gil (version bumps are still his PR to approve, now just visible).

**Machine:** none — this is CI config + a worktree script, nothing that runs locally beyond `swift test`.

**What's untested by me:** I cannot run `xcodebuild`/Xcode here. The exact on-disk location Xcode 26 writes its SwiftPM resolution state to under a fresh `-derivedDataPath` (`workspace-state.json`, most likely under `<D>/SourcePackages/`) is not something I can confirm empirically in this sandbox. I'm treating that as an implementation detail I resolve defensively — `find "$D" -name workspace-state.json` rather than a hardcoded nested path — and will adjust the `find` invocation if the pipeline's real CI run on `spike-app`/`mac-app` shows a different layout. This is not a product/design choice for the owner, just a thing the first real CI run against the generated Xcode project will confirm or correct.

## Tests to write first

From "How we'll try to break it" (all as cases in `scripts/check-fluidaudio-pin.test.mjs`, spawning the shell script against `mkdtempSync` fixtures, following `required-checks.test.mjs`'s style):

1. `from:` on CaptionCore's FluidAudio line → script fails, message names the file.
2. `upToNextMinor:` on EngineEval's FluidAudio line → fails.
3. `branch:` on SystemReplay's FluidAudio line → fails.
4. All three `Package.swift` say `exact: "0.17.5"` but one `Package.resolved` is still pinned at an older revision/version → fails (Package.swift/Package.resolved disagreement).
5. Two `Package.resolved` files pin different FluidAudio versions from each other (both say `exact:` in their manifests, but resolved state disagrees) → fails.
6. An "app-resolved" fixture file (`workspace-state.json` shape, `{"object":{"pins":[...]}}`) pinning a different FluidAudio version than CaptionCore's canonical pin, passed via `--app-resolved … --app-name spike` → fails, message names "spike".
7. Everything consistent (`exact:` everywhere, all resolved files and the app-resolved fixture agree) → passes, exit 0.
8. Every failure message's output contains the required sentence that a FluidAudio bump needs its own PR scored by the #273 replay.

Misuse cases the ticket's list didn't name, added because they're real ways this script breaks:

9. Malformed/empty JSON in a `Package.resolved` → script fails cleanly with a readable message, not a raw Python traceback.
10. `Package.swift` declares FluidAudio but its sibling `Package.resolved` has no FluidAudio pin at all → fails ("no FluidAudio pin found in …"), doesn't crash.
11. `--app-resolved` given an empty string or a path to a file that doesn't exist (simulating `find` finding nothing in CI) → hard failure, never silently treated as "nothing to check."
12. A `Package.swift` comment mentions `FluidAudio` and the word `from:` near it, but the actual dependency line is `exact:` → passes (regex anchored to the `.package(url: ".../FluidAudio.git", …)` line, not a bare substring match on `FluidAudio`).
13. Running the script twice in a row against the same fixtures → identical result both times (pure read-only, no stale state).
14. Invoked from a different working directory than the repo root → still finds the right files (mirrors `run-check.sh`'s own `top=$(cd "$(dirname …)/.." && pwd)` idiom).

Swift side (`Packages/CaptionCore/Tests/CaptionCoreTests/ThirdPartyNoticeTests.swift`):

15. New/extended test asserting NOTICE.md's `## FluidAudio` section contains the new sentence that the shipped version is pinned in the commit (mirrors the existing `testParakeetUltraIsCreditedWithTheChangeNoted` / Sortformer-section pattern of reading `NOTICE.md` directly and checking the section's content).

**Time/space complexity:** the checker is O(number of `Package.swift`/`Package.resolved` files in the repo) — a handful of small text/JSON files, no repo-wide content scan beyond excluding `.build`; negligible memory and disk. `swift test` behavior is unchanged (same resolved version, `from:`→`exact:` doesn't change what gets fetched).

## Decisions

None — the ticket's "What to build" and acceptance criteria fully specify the design; the only genuinely uncertain point (exact DerivedData file layout) is an implementation detail I resolve defensively, not a choice for the owner.

## Task List

1. `Packages/CaptionCore/Package.swift:15` — change `.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5")` to `exact: "0.17.5"`.
2. Update the now-stale comments that describe CaptionCore as using `from:`: `Packages/SystemReplay/Package.swift:19-21` and `Packages/EngineEval/Package.swift:17`.
3. Update `docs/perf/whole-system-replay-design.md:56-61` ("Pinning matters" paragraph) to note the drift risk it describes is now closed by this ticket's CI check, instead of leaving it as an open-ended warning.
4. Write `scripts/check-fluidaudio-pin.sh`: static repo-wide `exact:`/cross-package-agreement check (always runs), plus an optional `--app-resolved <path> --app-name <name>` mode reusing the `at-build.sh` pin-parsing snippet, with the required "own PR, scored by the #273 replay" sentence on every failure path, and a note (even on success) that FluidAudio's own transitive dependencies aren't separately pinned by this check.
5. Write `scripts/check-fluidaudio-pin.test.mjs` covering tests 1–14 above.
6. Add the `fluidaudio-pin` check to `.github/required-checks.json` (`cwd: "."`, `paths: ["Packages/*"]`, `command: ["bash", "scripts/check-fluidaudio-pin.sh"]`).
7. Add the matching `fluidaudio-pin` job to `.github/workflows/ci.yml` (`ubuntu-latest`, checkout with `fetch-depth: 0`, the `--affected` + run-check.sh steps, no Node/Xcode setup needed).
8. Extend the `spike-app` and `mac-app` entries' `command` in `.github/required-checks.json`: after the existing `xcodebuild … build` succeeds (and before the temp `$D` is removed by its trap), add `&& bash scripts/check-fluidaudio-pin.sh --app-resolved "$(find "$D" -name workspace-state.json | head -1)" --app-name spike` (resp. `mac`).
9. Run `node --test scripts/required-checks.test.mjs scripts/check-fluidaudio-pin.test.mjs` and `swift test --package-path Packages/CaptionCore` to confirm everything is green; confirm `node --test scripts/required-checks.test.mjs` still passes unchanged (drift test) with the new job/check added consistently.
10. Add a sentence to `NOTICE.md`'s `## FluidAudio` section (next to its licence line) stating the shipped version is pinned by the commit, and add/extend the matching assertion in `Packages/CaptionCore/Tests/CaptionCoreTests/ThirdPartyNoticeTests.swift` (test 15).
11. In the PR description, say plainly that the `--app-resolved` path discovery (`workspace-state.json` under DerivedData) is unverified by me locally and is exercised for the first time by the pipeline's own `spike-app`/`mac-app` CI runs.