Good — confirms `CFBundleVersion` (an `Int`-parseable string) is the existing app-build convention; `minAppBuild: Int` is consistent. I have everything needed. Here's the plan.

## North-star fit

**Reuses before adding anything new:** the per-file sha256/size verification algorithm already in `scripts/fetch-asr-models.sh`'s `check()` function and the `scripts/models/*.sha256` manifest convention (ADR 0025) — this PR expresses that same check as the `pack.json` JSON schema ADR 0029 decision 5 already settled (`id`, `kind`, `languages`, `engine`, `minAppBuild`, `sizeOnDisk`, `files`, `credit`) instead of inventing a new one. It follows the credit-line convention already established by `CreditsEntry.swift` / `ThirdPartyNotice.swift`, and the test style of `BundledSpeechModelTests.testManifestListsEveryComponentLoadLocalNeeds` / `ThirdPartyNoticeTests.swift`.

**Simplest sufficient approach:** a pure `Codable` type plus a stateless file-system verifier — no `AssetPackManager`, no download machinery, no Settings UI, no engine routing. That's exactly the slice the owner's latest comment asked for ("the first PR from the split only... Download/storage, Settings UI..., routing and migration follow as separate PRs"). No new package dependency: `CryptoKit` is an Apple system framework already implicitly available on these platform targets (like `Speech`/`AVFoundation` elsewhere in the package), not an SPM addition, so `Package.swift` doesn't change.

**Token/compute cost:** tiny and one-time — two small Swift files plus tests, no app-bundle size change (nothing is bundled differently), no new build step. The real cost this format exists to control — hashing hundreds of MB — is paid once per pack version by design (ADR 0029/0025), not at every launch; this PR's verifier reads in 1 MB chunks so it scales to a real ~500 MB pack without loading it whole into memory.

**Phone-OS / "as many languages as possible" direction:** this establishes the one shared pack format every future language pack (Hebrew, Serbian, more Parakeet languages) reuses, rather than a one-off shape per engine — the thing that makes "each language easy to add" true in code, not just in the doc.

**User capability:** no user-visible change. Nothing bundled, no fetch script, no `Package.swift`, no Xcode project file changes — the two models users have today keep shipping exactly as they do now. This PR is groundwork only.

**Explicitly out of scope for this PR** (per the issue's own re-scoping comment and the design doc's ticket ordering, §9): asset-pack download/storage, the Settings "Downloads" UI (needs a mock-up first, per the ios-app playbook's owner gate on any look change), `CaptionEngineRouting`/`EngineFallbackPolicy` wiring, and migrating the two bundled models into real `pack.json` files. Install-size measurement (the issue's third acceptance box) also waits for the packaging ticket, since this PR adds no bytes to any shipped artifact.

## Tests first

**`LanguagePackTests.swift`** (decode + validate):
1. A well-formed `pack.json` fixture decodes into `LanguagePack` with every field correct; round-trips through encode→decode unchanged.
2. Decoding tolerates an unknown extra top-level JSON key (forward compatibility: an older app must not choke on a newer pack — ADR 0029 decision 5's "minAppBuild" guarantee depends on this).
3. Decoding a malformed/truncated JSON blob throws a decode error, not a crash.
4. An unrecognized `engine` string, and an unrecognized `kind` string, each fail to decode.
5. Validation rejects: empty `id`; empty `credit`; empty `languages`; a blank language entry; empty `files`.
6. Validation rejects a duplicate file path inside `files`.
7. Validation rejects an unsafe file path: containing `..`, or absolute (`/etc/passwd`), or empty.
8. Validation rejects a non-positive `size`, and a `sha256` that isn't exactly 64 hex characters (too short, too long, non-hex content).
9. Validation rejects `minAppBuild <= 0`.
10. Validation rejects `sizeOnDisk` that doesn't equal the sum of `files[].size`, both when declared too high and too low (a stale/fabricated size).
11. A manifest with a few thousand file entries still validates without excessive time (huge input).
12. `isUsable(byAppBuild:)` is true at and above `minAppBuild`, false just below it (boundary).

**`LanguagePackVerifierTests.swift`** (folder + manifest, all against real temp-directory files, no fixtures checked in):
13. A folder matching the manifest exactly (right files, sizes, hashes) verifies `.ok`.
14. A missing file, an unexpected extra file, a size mismatch, and a content/hash mismatch are each reported — and several at once are all reported together, not just the first (mirrors `fetch-asr-models.sh`'s existing `problems` list).
15. A `.DS_Store` file present in the folder is ignored (same rule the existing Python `check()` already follows).
16. The target folder missing entirely reports every manifest file as missing, without throwing/crashing.
17. The target path pointing at a plain file instead of a directory throws a clear error rather than silently returning `.ok`.
18. A file that exists but can't be read (permission denied) is reported as a distinct problem, not silently skipped and not a crash.
19. Verification is read-only and idempotent: run twice in a row, same folder, identical result, and the folder's contents are untouched.
20. Running verification concurrently (multiple tasks on the same pack/folder at once) all return the same correct result with no crash or race.

## Task List

1. Add `Packages/CaptionCore/Sources/CaptionCore/LanguagePack.swift`: the `LanguagePack` struct (`Kind`, `Engine`, `FileEntry` nested types), `Codable`, a `LanguagePackError` enum, and a `validate()`/`decode(_:)` entry point enforcing the invariants in tests 2–12, plus the tiny `isUsable(byAppBuild:)` predicate.
2. Add `Packages/CaptionCore/Sources/CaptionCore/LanguagePackVerifier.swift`: `LanguagePackVerifier.verify(_:at:fileManager:)`, reusing the sha256/size-walk algorithm from `scripts/fetch-asr-models.sh`'s `check()`, with chunked (1 MB) `CryptoKit` hashing and the `PackVerificationProblem`/`PackVerificationResult` types covering tests 13–20.
3. Write `LanguagePackTests.swift` (tests 1–12).
4. Write `LanguagePackVerifierTests.swift` (tests 13–20), building fixture folders under `FileManager.default.temporaryDirectory` per test.
5. Run `swift test --package-path Packages/CaptionCore` and iterate until green; confirm no existing test changed behavior (fetch scripts, `Package.swift`, bundled-model tests untouched).
6. Write the PR description noting the scope boundary explicitly (download/storage, Settings UI, routing, migration are separate follow-up PRs per the issue's own comment) and that this touches only `Packages/CaptionCore` — no UI, no look-proof screenshots needed, nothing bundled changes.