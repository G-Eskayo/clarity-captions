1. [ ] Resolve the `text-processing-opt-out` and `lexicon-license-risk` decisions (owner, via the PR).
2. [ ] Research the LuxTTS lexicon's license (FluidInference/luxtts-coreml's HF card, FluidAudio's own issues, espeak-ng's dictionary-redistribution terms) and record it in `docs/research/evidence/2026-11-13-luxtts-lexicon-license.md` per `docs/research/evidence-log.md`.
3. [ ] If opting out: add `traits: []` to the FluidAudio dependency in `Packages/CaptionCore/Package.swift`; remove the stale `nemotextprocessing` entries from `ThirdPartyNotice.swift`, `CreditsEntry.coveredByFullLicenseTexts`, and NOTICE.md.
4. [ ] Add the source-scan regression test (Test 1).
5. [ ] Depending on the lexicon decision: add a `luxtts` entry + NOTICE.md section + test (Test 3, branch A), or add the stripping/vendoring change and its verification (branch B/C).
6. [ ] Build Apps/Spike for the iOS Simulator before and after the change; measure `.app` size both times (`du -sh`, ADR 0014's existing manual style); append a dated subsection to `docs/adr/0014-bundle-diarizer-models-in-the-app.md` with both numbers and the decision.
7. [ ] Run `swift test --package-path Packages/CaptionCore` and the spike-app verify step; confirm both green.
8. [ ] Re-run `ThirdPartyNoticeTests` and manually confirm the shipped bundle matches the updated notice list (AC #4).
9. [ ] Write the PR (`Refs #32`/`Closes #32`): state what was measured, that no real build/device run happened in this session, and carry the Decisions block.