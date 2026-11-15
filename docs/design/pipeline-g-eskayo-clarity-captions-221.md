## North-star fit

- **Reuses before adding anything new:** the sha256-manifest-and-verify pattern already shipped twice (ADR 0025/0014) — `scripts/fetch-asr-models.sh`'s Python `check()` (file-set diff, size-then-hash, `.DS_Store` skip, streamed 1 MB-chunk hashing) and `scripts/models/*.sha256`'s `sha256  size  path` rows — and the credit/licence vocabulary already in `ThirdPartyNotice.swift` / `CreditsEntry.swift` (name, licence, note, source). This PR ports that *pattern* into a typed, testable Swift shape (`pack.json`, ADR 0029 §4) instead of inventing a new one. `CaptionEngineChoice`/`SealModel` (`EngineFallbackPolicy.swift`) is the existing "engine type" vocabulary (Parakeet/Apple/Seal's own) the ticket's "engine type" field must agree with, not duplicate.
- **Simplest sufficient approach:** a pure `Codable` struct plus a pure, non-throwing verifier function — no actors, no I/O beyond reading a folder and hashing files, no new SwiftPM dependency (CryptoKit is an Apple system framework, already implicitly available wherever Foundation is, same footing as `AVFoundation` elsewhere in the package — not a new dependency under the owner's gate, which is about added SwiftPM packages/network).
- **Scope, per the issue's latest comment:** *only* "pack format and manifest (sha256 checks, engine type, licence and credit lines)". Download/storage, Settings UI, routing (`CaptionEngineFactory`/`EngineFallbackPolicy` reading the table), and migrating the two bundled models onto real `pack.json` files are later PRs in the same split and are explicitly **not** touched here — no `scripts/fetch-asr-models.sh` changes, no `project.yml`/Spike app changes, no new `Resources/Models/...` folder reference. That last point directly avoids the class of failure the first three attempts hit ("Target CaptionSpike has a missing source directory ... ParakeetUltra"): this PR adds Swift source + tests to `CaptionCore` only, nothing the Xcode project spec needs to see.
- **Where it spends tokens:** new code, but it's the one seam every later PR in the split (download/storage, routing, migration) needs to build on — compounding leverage, not a one-off.
- **More capable, not more passive:** this is backend plumbing with no user-facing behavior; the test is whether it leaves *future PRs* safer (a corrupted or tampered pack is caught before it's trusted), not the end user directly yet.
- **No Decisions needed.** The schema (`id`, `kind`, `languages`, `engine`, `minAppBuild`, `sizeOnDisk`, `files[]`, `credit`) is already settled in ADR 0029 §4's worked example — nothing here is an open design choice for the owner to pick between.
- **Machine:** this worktree (CaptionCore is platform-agnostic Swift, `swift test` runs anywhere `DEVELOPER_DIR` is set, no simulator needed).

## Tests first

The issue has no "How we'll try to break it" section, so per instructions I derive the adversarial cases myself (bad/empty/huge/malformed input, each dependency failing, repeats/concurrency, wrong permissions, a person's mistake), scoped to what this PR actually ships: decoding/validating `pack.json` and verifying a folder against it. No network or download code exists yet in this slice, so the issue's "offline test: after download, no network" lands in the download/storage PR, not here.

**`PackManifestTests.swift` — decoding and schema validation**
1. A valid `pack.json` (ADR 0029 §4's own example, Hebrew Parakeet) decodes to the expected `PackManifest`, and encoding it back round-trips to an equal value.
2. Malformed JSON (truncated bytes, non-UTF8 garbage) throws a decoding error instead of crashing.
3. JSON missing a required field (`id`, `files`, etc.) throws.
4. An unknown `kind` string fails to decode (not silently accepted as something else).
5. Empty `files` array is rejected (a pack naming zero files is a maintainer mistake, not a valid pack).
6. Empty `languages` array is rejected (same reasoning).
7. A `sha256` value that isn't exactly 64 lowercase hex characters is rejected.
8. A negative or zero file `size` is rejected.
9. `minAppBuild` below 1 is rejected.
10. Duplicate `path` entries within `files` are rejected (ambiguous — which one wins?).
11. Empty `credit` string is rejected (every bundled model must carry a credit line, ADR 0025 decision 4).

**`PackVerifierTests.swift` — folder-vs-manifest verification**
12. A folder whose files exactly match the manifest's paths, sizes and hashes verifies clean (no problems).
13. A missing manifest file is reported as `missing`, not a crash.
14. An extra file not in the manifest is reported as `unexpected`.
15. A file whose size differs from the manifest (truncated/corrupt download) is reported as a size mismatch, and the verifier does **not** waste time hashing it.
16. A file with the right size but different bytes (bit flip, same length) is reported as a checksum mismatch.
17. The folder doesn't exist at all → a clear "folder missing" problem, not an uncaught `FileManager` error.
18. An empty folder (zero files) → every manifest file reported missing, none crash.
19. A stray `.DS_Store` in the folder is ignored (matches the existing Python checker, macOS artifact, not "unexpected").
20. A file whose size is large enough (several MB, synthetic) that it exercises the chunked/streaming hash path still verifies correctly — proxy for "huge input doesn't blow up" since a unit test can't directly assert bounded memory.
21. A file with its read permission removed (`chmod`) is reported as a readable problem (e.g. `unreadable`), not a fatal error or uncaught `NSError` — the "wrong permissions" case.
22. Running `verify` concurrently from multiple tasks on the same read-only folder/manifest gives identical results every time (pure function, no shared mutable state) — the "repeats and concurrency" case.
23. Verifying the same (valid) folder twice in a row gives the same clean result (idempotent, as the shell script's `check()` already assumes).

## Task List

1. Add `Packages/CaptionCore/Sources/CaptionCore/PackManifest.swift`: `PackManifest` (`id`, `kind`, `languages`, `engine`, `minAppBuild`, `sizeOnDisk`, `files`, `credit`), nested `PackManifest.Kind` (`speech`/`diarizer`/`translation`) and `PackManifest.File` (`path`/`size`/`sha256`), `Codable & Equatable & Sendable`, matching ADR 0029 §4's `pack.json` field names exactly.
2. Add a throwing validator (`PackManifest.validate()` or a throwing `PackManifest(json:)` factory) enforcing: non-empty `files`/`languages`, 64-char lowercase hex `sha256`, non-negative `size`, `minAppBuild >= 1`, no duplicate `path`s, non-empty `credit`.
3. Write `PackManifestTests.swift` covering tests 1–11 above, written before (or alongside, verified red-then-green) the validator logic.
4. Add `Packages/CaptionCore/Sources/CaptionCore/PackVerifier.swift`: a pure `PackVerifier.verify(_:in:fileManager:)` that walks a folder (skipping `.DS_Store`), diffs its file set against the manifest, and for files present in both checks size first and only then streams a chunked `CryptoKit.SHA256` hash (mirroring `fetch-asr-models.sh`'s `check()`), returning `[PackVerificationProblem]` (`missing`, `unexpected`, `sizeMismatch`, `checksumMismatch`, `folderMissing`, `unreadable`) rather than throwing, so callers can report state instead of catching exceptions.
5. Write `PackVerifierTests.swift` covering tests 12–23 above, building each fixture folder under `FileManager.default.temporaryDirectory` with a per-test `UUID()` subfolder (the existing test convention), cleaning up after itself.
6. Run `swift test --package-path Packages/CaptionCore` locally; confirm all new tests are red before the implementation and green after, and that no existing test (`BundledModelsTests`, etc.) regresses.
7. State in the PR description: time/space complexity (`validate` is O(files); `verify` is O(total pack bytes) time with O(1) extra memory per file via chunked hashing, O(files) for the problem list and folder listing); that no app/Xcode project files changed; and that this is untested on a real device/pack (it's pure Swift over a local folder, exercised only by `swift test`, no Simulator build involved) — the issue's "offline: after download, no network" criterion is left to the download/storage PR, since no download code exists yet.