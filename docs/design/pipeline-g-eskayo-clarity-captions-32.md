## North-star fit

- **Reuses before adding anything new:** the `ThirdPartyNotice` / `CreditsEntry` struct pattern (`Packages/CaptionCore/Sources/CaptionCore/ThirdPartyNotice.swift`, `CreditsEntry.swift`) and its test suite (`Packages/CaptionCore/Tests/CaptionCoreTests/ThirdPartyNoticeTests.swift`) — the repo's established way to credit or re-credit a bundled third-party component (used for Parakeet Ultra, the Hebrew model, Sortformer's #271 license correction). Also reuses the source-scanning regression-test pattern in `OneScreenSourceRulesTests.occurrences(of:in:)` (`Packages/CaptionCore/Tests/CaptionCoreTests/OneScreenSourceRulesTests.swift`) to lock in that our code never calls the FluidAudio surface being dropped, and ADR 0014's existing append-only "License re-check / Measured" style for recording this ticket's findings, rather than inventing a new doc.
- **Simplest sufficient approach:** FluidAudio already ships an upstream-supported, zero-risk opt-out for the text-processing engine — a `NemoTextProcessing` trait in its own `Package@swift-6.2.swift` (which matches our `swift-tools-version: 6.2`), built by its maintainers specifically for "ASR/VAD/diarization-only apps" like ours. Using it is a one-line `Package.swift` change, not a fork. For the LuxTTS lexicon, which has *no* such opt-out, the simplest sufficient action is to pin down its license and credit it (it's ~1 MB against a 229 MB diarizer model) — vendoring/forking FluidAudio to save a megabyte would be disproportionate unless the license is actually incompatible.
- **Where it spends tokens:** the lexicon's license can't be resolved in this planning sandbox (no network access) — that research is isolated to one implementation task rather than repeated.
- **Phone-OS direction:** neutral; this is app-size/compliance hygiene, not a capability.
- **User capability:** no visible change for Seal's users; it shrinks the download slightly and closes a licensing gap behind ADR 0007's "free" promise. N/A for screenshots (pr-requirements.md: internal/config change, no visible effect).

## Findings (from the vendored FluidAudio checkout at `Packages/CaptionCore/.build/checkouts/FluidAudio`, pinned 0.17.5 — no network needed for these)

1. FluidAudio exports exactly **one product**, `FluidAudio` — there is no separate diarizer-only product today.
2. FluidAudio **does** define an opt-out trait, `NemoTextProcessing`, in `Package@swift-6.2.swift` (their tools-version ≥6.2 manifest). Declaring our dependency as `.package(url: ..., from: "0.17.5", traits: [])` would drop the statically-linked `NemoTextProcessing` xcframework entirely (FluidAudio's own comment: "~8 MB per slice, a prebuilt Rust staticlib").
3. **Confirmed by source audit:** nothing in `Packages/CaptionCore` calls FluidAudio's `TextNormalizer`/`NemoTextNormalizer`/any TTS API (`ParakeetBackend.swift` calls only `AsrManager.transcribe`, which never routes through ITN). So the opt-out changes zero observable behavior today.
4. The LuxTTS lexicon (`luxtts_en_us_lexicon.tsv.zz`) is bundled a **different** way: `.process("TTS/LuxTts/G2p/Resources")` on the main `FluidAudio` target's `resources:` list, unconditionally — not trait-gated. The `NemoTextProcessing` opt-out does **not** remove it; FluidAudio's manifest offers no switch for it.
5. FluidAudio's own docs (`Documentation/TTS/LuxTts.md`) describe the lexicon as "harvested offline from espeak-ng via piper_phonemize... instead of bundling espeak" — derived pronunciation data, not espeak-ng's own GPL-3.0 code. It genuinely isn't in FluidAudio's `ThirdPartyLicenses/` folder (confirmed: only `JapaneseG2P`, `KokoroAneSpanishFrenchG2P`, `NemoTextProcessing`, `fastcluster`, `vbx` are there), matching the issue's own finding. Pinning down whether/under-what-license that derived data can be redistributed needs network research this sandbox can't do.

## Decisions
<!-- marvin:decisions -->
### text-processing-opt-out: Opt out of FluidAudio's `NemoTextProcessing` trait in Package.swift?
- [ ] Yes — add `traits: []` to the FluidAudio dependency, drop the ~8 MB binary, remove its now-stale NOTICE.md/ThirdPartyNotice.swift entry
- [ ] No — leave it linked; just record the measured size in ADR 0014 and close that half of the ticket

### lexicon-license-risk: If the LuxTTS lexicon's license can't be pinned down with confidence, how should we handle it? (only decides the fallback — a clear compatible license just gets credited, no decision needed)
- [ ] A: Credit it with the best-available attribution and a stated confidence level, accept the residual risk
- [ ] B: Strip it from the shipped bundle with a build-phase script deleting it from `FluidAudio_FluidAudio.bundle` before signing
- [ ] C: Vendor/fork only the diarizer-relevant FluidAudio sources instead of the whole package
- [ ] D: Open a separate follow-up ticket for the lexicon alone; close out only the text-processing half of #32 now

## Tests (first)

This ticket touches build config and licensing bookkeeping, not user input or a network surface, so injection/XSS/flood classes don't apply; the adversarial angle is a wrong claim about what's in the binary, a silent re-introduction of the dropped dependency, and a build that stops honoring the opt-out.

1. New source-scan test reusing `occurrences(of:in:)` from `OneScreenSourceRulesTests.swift`, run over `Packages/CaptionCore/Sources`, asserting no call to `TextNormalizer(`/`NemoTextNormalizer(` — locks in that opting out is safe now and stays safe.
2. Update `ThirdPartyNoticeTests` so the suite fails if `ThirdPartyNotice.all`/NOTICE.md still claims a `nemotextprocessing` notice once it's no longer linked — an over-claim is as wrong as an under-claim.
3. New test (pattern: `testTheHebrewEngineIsCreditedWithTheChangeNoted`) for the LuxTTS lexicon: asserts a matching notice entry + NOTICE.md section with the researched license (branch A), or that the resource is actually absent from the build (branch B/C).
4. Dependency-failure case: `swift test --package-path Packages/CaptionCore` and the spike-app simulator build both stay green with the trait removed — a toolchain that doesn't understand `traits:` must fail loudly, not silently re-link.
5. AC #4's "re-run the credits check" literally: after the change, re-run `ThirdPartyNoticeTests` and manually confirm the built bundle's contents match the updated notice list.
6. Person's mistake / stale state: note in the ADR 0014 addendum that any future FluidAudio version bump must re-check this ticket's findings (mirrors ADR 0014's existing "License re-check" pattern).

## Task List

1. [ ] Resolve the `text-processing-opt-out` and `lexicon-license-risk` decisions (owner, via the PR).
2. [ ] Research the LuxTTS lexicon's license (FluidInference/luxtts-coreml's HF card, FluidAudio's own issues, espeak-ng's dictionary-redistribution terms) and record it in `docs/research/evidence/2026-11-13-luxtts-lexicon-license.md` per `docs/research/evidence-log.md`.
3. [ ] If opting out: add `traits: []` to the FluidAudio dependency in `Packages/CaptionCore/Package.swift`; remove the stale `nemotextprocessing` entries from `ThirdPartyNotice.swift`, `CreditsEntry.coveredByFullLicenseTexts`, and NOTICE.md.
4. [ ] Add the source-scan regression test (Test 1).
5. [ ] Depending on the lexicon decision: add a `luxtts` entry + NOTICE.md section + test (Test 3, branch A), or add the stripping/vendoring change and its verification (branch B/C).
6. [ ] Build Apps/Spike for the iOS Simulator before and after the change; measure `.app` size both times (`du -sh`, ADR 0014's existing manual style); append a dated subsection to `docs/adr/0014-bundle-diarizer-models-in-the-app.md` with both numbers and the decision.
7. [ ] Run `swift test --package-path Packages/CaptionCore` and the spike-app verify step; confirm both green.
8. [ ] Re-run `ThirdPartyNoticeTests` and manually confirm the shipped bundle matches the updated notice list (AC #4).
9. [ ] Write the PR (`Refs #32`/`Closes #32`): state what was measured, that no real build/device run happened in this session, and carry the Decisions block.