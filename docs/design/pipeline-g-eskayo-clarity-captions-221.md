## North-star fit

**Reuses:** the manifest format and verification algorithm already in `scripts/fetch-asr-models.sh`'s `check()` (sha256+size per file, "missing"/"unexpected"/"size mismatch"/"checksum mismatch" problem list, `manifest is empty` guard on zero files) — this is literally ADR 0025's pattern the ticket asks to reuse. It reuses the engine-name vocabulary already in `TranscriptionEngine.swift`'s `SpeechRecognizerSetup` (`.apple` / `.parakeet` / `.zipformer`) and `EngineFallbackPolicy.swift`'s `SealModel` instead of inventing new engine names. It reuses the exact `pack.json` field list already agreed in `docs/design/smallest-install-and-language-packs.md` §4 (`id`, `kind`, `languages`, `engine`, `minAppBuild`, `sizeOnDisk`, `files[{path,size,sha256}]`, `credit`) and the one-line "what it is + its licence" credit style already used by `CreditsEntry.swift` (e.g. `"The voice model. NVIDIA Open Model License."`).

**Simplest sufficient approach:** a single new pure Codable type (`LanguagePack`) plus one verification method, in CaptionCore only. No seam into `TranscriptionEngine`, no fetch-script changes, no UI, no `pack.json` files written for the real bundled models yet — those are explicitly the next PRs per the issue's own split and the 2026-11-04 comment ("This run: the first PR from the split only... Download/storage, Settings UI, routing and migration follow as separate PRs"). Doing less here is correct, not a shortcut: wiring it into the live download/routing path with no download mechanism yet would be dead code nobody could exercise end to end.

**Tokens:** small, additive, one file + one test file; no network, no Simulator build needed since nothing touches the app layer or SwiftUI — this ticket stays entirely inside `swift test --package-path Packages/CaptionCore`. No spike-app/look-proof stage applies.

**Capability:** this is pure plumbing (a manifest format and a checker) — it doesn't change what the user can do yet, it's the foundation the download/Settings/routing PRs build on. No north star argues against building it; it's a enabling step for ADR 0029's "best engine for every language" goal.

**No Decisions needed.** Every field is already settled by ADR 0029/0031 and the approved design doc — this PR is a direct translation of an already-agreed schema into Swift, not a new design choice. I did find one implementation detail the design doc left informal (its example uses `"engine": "parakeet-tdt"`, a model-card name) which I'm resolving by reusing the three names the code already has (`apple`/`parakeet`/`zipformer`) rather than inventing a fourth vocabulary — not surfacing this as an owner Decision because it's a mechanical fit to existing code, not a new product choice.

## Why no PR exists yet from earlier attempts

`gh pr list` shows no PR tied to #221 (closest is the merged design PR #205 for #200). The worktree is clean and tracks `origin/main` — the prior failed runs (comments: "code review found must-fix issues," build crashes on a missing `ParakeetUltra` resources directory) left nothing committed here to build on or avoid repeating blindly. I'm designing from the ADR/design doc directly rather than guessing at what the must-fix issues were.

## Tests first

The issue has no "How we'll try to break it" section, so per instructions I derived misuse cases myself, grounded in what `verify()` and the `Codable` decode actually have to survive:

1. `testDecodesTheAgreedPackJSONShape` — decodes the *exact* JSON block from `docs/design/smallest-install-and-language-packs.md` §4 (the real collaborator: the agreed schema, not a invented fixture) into `LanguagePack` with every field matching.
2. `testEncodeDecodeRoundTrips` — encode → decode → equal, guards schema drift silently breaking compatibility.
3. `testUnknownKindOrEngineThrowsInsteadOfDefaulting` — malformed input: a `kind`/`engine` string outside the known set throws `DecodingError`, never silently falls back to some default.
4. `testMissingRequiredFieldThrows` — malformed/empty input: JSON missing `id` (or any required key) throws, doesn't crash or produce a half-built value.
5. `testVerifyPassesWhenFolderMatchesManifestExactly` — the happy path.
6. `testVerifyFailsOnMissingFile` — a file the manifest lists isn't on disk.
7. `testVerifyFailsOnUnexpectedFile` — folder has an extra file (a person's mistake: left a stray file during packaging).
8. `testVerifyFailsOnSizeMismatchWithoutHashingTheWrongFile` — a file present with the wrong byte count fails on size alone (ports the shell script's "size mismatch → continue, don't hash"); covers the "huge malformed input" case too, since a pack can declare a multi-hundred-MB size that doesn't match a small/garbage file without the test needing to materialize gigabytes.
9. `testVerifyFailsOnChecksumMismatchWithMatchingSize` — same size, different bytes.
10. `testVerifyOnEmptyManifestFails` — empty `files: []` is rejected ("manifest is empty"), not treated as vacuously OK — this is a tampering/misuse case the shell script already guards against and the Swift port must not regress.
11. `testVerifyRejectsDuplicateManifestEntries` — two entries for the same `path` (a hand-edited `pack.json` mistake) is flagged as a problem rather than silently keeping only one.
12. `testVerifyOnMissingFolderFailsCleanly` — folder itself doesn't exist (dependency failure: the filesystem isn't there) — reported as a problem, not a thrown/crashing error.
13. `testVerifyReportsEveryProblemAtOnceInDeterministicOrder` — missing + unexpected + mismatch together, order independent of filesystem iteration order, so repeat runs on identical input always produce identical output (repeats/determinism).
14. `testVerifyIsSafeUnderConcurrentCalls` — many concurrent `verify()` calls (same pack, same folder, from a `TaskGroup`) all return the same result with no crash or shared-state corruption — guards against a future cache/singleton creeping in.

Not tested here, stated plainly: an actual "no network after download" test, because `verify()` takes no `URLSession`/networking capability at all — there is nothing to assert against until the download/storage PR exists. A real file-permissions-denied test is flagged as environment-dependent (root/CI sandboxing can defeat `chmod`), so I'm covering that case by code construction (no force-unwraps; any `FileManager`/hashing error becomes a reported problem, never a crash) rather than a flaky permissions test.

## Task List

1. Add `Packages/CaptionCore/Sources/CaptionCore/LanguagePack.swift`: `LanguagePack` (Codable, Equatable, Sendable) with nested `Kind` (`speech`/`diarizer`/`translation`), `Engine` (`parakeet`/`zipformer`/`apple`, matching `SpeechRecognizerSetup`), `File` (`path`/`size`/`sha256`), and the top-level fields `id`, `kind`, `languages`, `engine`, `minAppBuild`, `sizeOnDisk`, `files`, `credit` per ADR 0029 §4/design doc §4.
2. On the same type, add `verify(in folder: URL, fileManager: FileManager = .default) -> PackVerification` (`.ok` / `.failed(problems: [String])`), a Swift port of `fetch-asr-models.sh`'s `check()`: empty-manifest guard, duplicate-path guard, missing/unexpected file detection, size check before hashing, SHA-256 via `CryptoKit` (system framework, no new package dependency), problems collected and returned in deterministic (sorted) order.
3. Add `Packages/CaptionCore/Tests/CaptionCoreTests/LanguagePackTests.swift` with the 14 tests above, written and failing before step 1/2 land (TDD), using `FileManager.default.temporaryDirectory` fixtures created and torn down per test — no new `Tests/CaptionCoreTests/Fixtures` files needed.
4. Run `swift test --package-path Packages/CaptionCore` to green, then review the diff for anything touching `TranscriptionEngine`, `EngineFallbackPolicy`, the fetch scripts, or any bundled-model path — there should be none, confirming nothing already shipped can break.
5. State in the PR which behavior is untested (per the playbook): nothing UI-facing changes, so no Simulator screenshots are needed this PR; call out explicitly that the no-network guarantee for the pack-download path itself isn't testable yet because download/storage is a separate, not-yet-built PR.