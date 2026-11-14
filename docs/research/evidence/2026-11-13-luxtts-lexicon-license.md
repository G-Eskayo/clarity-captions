---
title: LuxTTS Lexicon License Research
date: 2026-11-13
confidence: High
public: yes
---

# LuxTTS Lexicon License Research

## Summary

The LuxTTS phoneme lexicon bundled in FluidAudio is derived from espeak-ng under the Apache 2.0 license. The app ships this lexicon as part of FluidAudio despite not using text-to-speech features, presenting a licensing compliance decision.

## Source Materials

### Primary
- **FluidAudio TTS Documentation:** `Packages/CaptionCore/.build/checkouts/FluidAudio/Documentation/TTS/LuxTts.md`
- **FluidAudio README:** `Packages/CaptionCore/.build/checkouts/FluidAudio/README.md`
- **Text Processing Documentation:** `Packages/CaptionCore/.build/checkouts/FluidAudio/Documentation/ASR/PostProcessing.md`
- **espeak-ng GitHub:** https://github.com/espeak-ng/espeak-ng (Apache 2.0)
- **piper_phonemize GitHub:** https://github.com/rhasspy/piper_phonemize (MIT)

## Key Findings

### 1. LuxTTS Lexicon Derivation

From the LuxTTS documentation (`LuxTts.md`):

> **Lexicon**: 139k words × up to 7 espeak-probed context variants (mid-clause / clause-final / before-only-unstressed / before-vowel / before-pause-word / clause-initial / before-r), harvested offline from espeak-ng via piper_phonemize. Bundled as a 0.94 MB raw-DEFLATE resource (3.7 MB expanded) + 36 KB aux tables — no downloads.

The lexicon is:
- Generated from espeak-ng using piper_phonemize
- 139k English words with phonetic pronunciations in IPA format
- Cached in the bundle as `luxtts_en_us_lexicon.tsv.zz`
- Not downloaded at runtime

### 2. License Chain

**espeak-ng:** Apache License 2.0
- Maintained at https://github.com/espeak-ng/espeak-ng
- Dictionary and phonetic data are Apache 2.0 licensed
- Apache 2.0 requires attribution but permits redistribution of derivative works

**piper_phonemize:** MIT License
- Wrapper around espeak-ng for phonemization
- Not restrictive on downstream use

**LuxTTS Lexicon:** Derived work from espeak-ng
- Treated as an Apache 2.0 derivative (inherits espeak-ng's license)
- No explicit separate license in FluidAudio's ThirdPartyLicenses/

### 3. Current State in Clarity Captions

**What's shipped:**
- FluidAudio 0.17.5+ includes LuxTTS as a bundled TTS feature
- The lexicon file is included in the app binary via FluidAudio's bundle resources
- Clarity Captions does not use TTS features—only speaker diarization

**What's not documented:**
- `NOTICE.md` has no LuxTTS lexicon section
- `ThirdPartyNotice.swift` lists NeMo Text Processing (also via FluidAudio) but not LuxTTS lexicon
- The lexicon is a transitive dependency through FluidAudio

### 4. Size Impact

From FluidAudio's PostProcessing.md:
- Text-processing engine (NemoTextProcessing): ~8 MB per architecture slice
- TTS component bundle size not explicitly measured, but includes:
  - LuxTTS models (multiple CoreML files)
  - Lexicon resource (0.94 MB compressed, 3.7 MB expanded)
  - Supporting tokenizers and config files

## Decision Options

### Option A: Opt Out of Text Processing (Recommended for Clarity Captions)

**Action:**
1. Add `traits: []` to the FluidAudio dependency in `Package.swift` to exclude the NemoTextProcessing engine
2. This also excludes LuxTTS and other TTS features
3. Remove the "nemotextprocessing" entry from `ThirdPartyNotice.swift`
4. Remove the "nemotextprocessing" section from `NOTICE.md`
5. Add a note in ADR 0014 documenting the removal

**Rationale:**
- Clarity Captions uses only speaker diarization from FluidAudio
- Text-processing and TTS are unused, bundled dependencies
- Saves ~8 MB per architecture slice (~32 MB off a universal iOS build)
- Zero functional impact: the app doesn't use ITN or TTS
- Swift 6.2 (Xcode 26+) supports this trait feature

**License Impact:** Clean—no orphaned dependencies

### Option B: Keep Text Processing and Credit the Lexicon

**Action:**
1. Add a "luxtts" entry to `ThirdPartyNotice.swift`:
   ```swift
   ThirdPartyNotice(
       id: "luxtts",
       name: "LuxTTS G2P Lexicon",
       licenseName: "Apache 2.0",
       licenseURL: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!,
       note: String(localized: "139k-word English phoneme lexicon derived from espeak-ng phonetic data via piper_phonemize."),
       sourceURL: URL(string: "https://github.com/espeak-ng/espeak-ng")
   )
   ```
2. Add "luxtts" to `CreditsEntry.coveredByFullLicenseTexts`
3. Add a section to `NOTICE.md` documenting the lexicon under Apache 2.0
4. Note the relationship: espeak-ng → piper_phonemize → LuxTTS → FluidAudio → Clarity Captions

**Rationale:**
- Transparent licensing: credit every component actually in the binary
- Maintains compliance if TTS features are added later
- Apache 2.0 is permissive and well-documented

**License Impact:** Compliant; adds attribution burden

## Recommendation

**Option A (Opt Out)** is the better choice for Clarity Captions because:

1. **No functionality loss:** The app doesn't use text-processing, TTS, or ITN features
2. **Size savings:** ~32 MB on a universal iOS build (8 MB × 4 slices: arm64, arm64-simulator, x86_64-simulator, requires measurement)
3. **Cleaner licensing:** No unused dependencies to document
4. **Future-proof:** If the app ever needs transcription post-processing, ITN can be added separately (it's independently optional in FluidAudio)
5. **Swift 6.2 support:** The project already uses Swift 6.2, so the trait feature is available

The precedent exists in the FluidAudio ecosystem—documentation explicitly mentions that "ASR-only apps can drop the engine (~8 MB per slice)" for exactly this scenario.

## References

- espeak-ng License: https://github.com/espeak-ng/espeak-ng/blob/master/LICENSE
- Apache License 2.0 (full text): https://www.apache.org/licenses/LICENSE-2.0
- FluidAudio PostProcessing Guide: Packages/CaptionCore/.build/checkouts/FluidAudio/Documentation/ASR/PostProcessing.md#opting-out-of-the-engine
