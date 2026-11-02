# 0029 — Models download as packs; the base install is the app, and the best engine for the language follows

## Status

Proposed (2026-10-29, #200; revised the same day with the owner's revised answers on PR #205). Draft: the owner has
answered `base`, `english-pack`, `speaker-pack`, `network-rule`, `hosting` and `cellular`; `update-path`,
`unused-engine` and `parakeet-unmeasured` are open on the design PR. If accepted, it supersedes [[0014]] decision 1
and [[0025]] decisions 3 and 7 (models bundled, GitHub-hosted) for App Store and TestFlight builds, and [[0025]]'s
"Parakeet for English only". It amends [[0001]]'s "on-device only" wording. Design:
`docs/design/smallest-install-and-language-packs.md` §3, §4 and §6.

## Context

- The 1.1 Release build is **765 MB**: Parakeet Ultra 498 MB, Sortformer 241 MB, and everything else 26 MB
  (`docs/perf/install-size-2026-10-29.md`). Every user pays for both models whatever language they caption in.
- The owner wants the smallest install that works, growing only when the user does something that needs more
  (#200). Revised 2026-10-29: **the best engine is the standard for every language and region**, with no "better
  English" option. What gets skimmed is engines for languages the user doesn't use.
- #158 measured Parakeet Ultra beating Apple in Spanish (2.8% vs 4.0% WER), French (4.5% vs 7.5%) and German (4.4%
  vs 7.2%), with intervals that don't overlap (E19). The app uses it only for English today.
- Parakeet Ultra is **one model for 25 European languages**: one encoder (about 461 of its 498 MB), one decoder and
  joint network, one shared vocabulary, and it detects the language from the audio (E14). FluidAudio's Parakeet v3
  path takes no language argument (evidence `2026-10-29-parakeet-is-one-pack-for-all-its-languages`).
- Apple-hosted asset packs (Background Assets, iOS/iPadOS/macOS 26.0+) download at install (`essential`), start at
  install and finish in the background (`prefetch`), or only when the app asks (`onDemand`). The app can track them
  and remove them, they update on their own schedule, and Apple hosts them free (200 GB per app). Picking a pack by
  language at install needs iOS 27. Citations in the design doc §4.
- Seal already captions without Parakeet: Apple's engine is the fallback when the model is missing ([[0025]] 2).
- Hebrew and Serbian need models Apple may not have or does badly (#201, #204). Bundling every language would grow
  the app for everyone.

## Decision (proposed)

1. **The base install is the app** (code, every UI language, fonts; about 26 MB) **with Apple's speech engine**. It
   captions from the first launch.
2. **Seal picks the best engine for each caption language**, from three groups, and nobody picks it in Settings
   ([[0013]]):
   - **Parakeet** for the languages it covers once each is measured to match or beat Apple (#158's rule, [[0026]]
     §3). Today English, Spanish, French, German, Italian and Portuguese (#234 measured the last two: every
     language both engines caption).
   - **Apple's built-in engines** (SpeechTranscriber, else DictationTranscriber; 0 MB to Seal) where Parakeet doesn't
     reach, hasn't been measured yet, or loses.
   - **Seal's own packs** where neither is good enough (Apple has nothing, or the better of the two is above 15%
     WER), once a Seal model measures better: Hebrew if it beats Apple (#201), Serbian (#204).
   The language → engine table lives in CaptionCore and ships with the app.
3. **Every Seal model is a pack**: speaker labels (Sortformer), **one shared Parakeet pack** for all its languages
   (498 MB, 6-bit), and one pack per Seal language model. Each pack is an Apple-hosted asset pack on Apple platforms
   and a Play Asset Delivery (or AI) pack on Android.
4. **Who gets what, when:**
   - **Speaker labels** for everyone: `prefetch`, starting with the install and on update.
   - **The caption language's engine** is requested by Seal at first launch (`onDemand`), with no question asked.
     Only the engine that language needs downloads: a Hebrew or Japanese phone never gets Parakeet. Choosing a caption
     language whose engine isn't on the device downloads it the same way. Apple's engine captions meanwhile.
   - Seal doesn't use the system's language-based picking, which needs iOS 27 and follows the UI language, not the
     caption language.
5. **Each pack carries `pack.json`**: id, kind, languages, minimum app build, sizes, per-file sha256 (the [[0025]]
   manifest as JSON) and its credit line. Seal verifies each pack version once before first use. A model that older
   builds can't load gets a **new pack id**, never a new version of the same one, because a live pack reaches every
   installed version.
6. **No model swaps mid-session.** A pack that lands or updates is used from the next Start.
7. **Debug, simulator and evaluation builds keep bundling** the models through the existing fetch scripts. One
   seam resolves bundle first, then packs.
8. **Settings > Downloads** lists Seal's packs with real sizes, naming the languages each engine captions, plus what
   iOS keeps for Seal (speech and translation languages) without size or delete. The engine for the caption
   language has no Delete; speaker labels and engines no kept language uses do.
9. **"On-device only" is reworded** (CONTEXT.md, on acceptance):
   > Everything Seal does with sound and text runs on the device, with no network call while it runs. The models it
   > uses (Apple's speech and translation assets, and Seal's own packs) download once: at install, at first run, or
   > when the user adds a language or feature. They come only from Apple's servers, carry no user data, and after that
   > every feature works with no network. Losing the network never stops captions.

## Consequences

- The base drops from 765 MB to about 26 MB, then 267 MB once speaker labels land. A phone in a Parakeet language
  (English, Spanish, French, German, Italian, Portuguese today) ends at 765 MB, now with the best engine for all six. A
  phone whose language Apple does best (Japanese, Korean, Chinese, and Hebrew on Apple's dictation engine) ends at 267 MB.
  Bilingual use costs nothing extra within Parakeet's languages: one pack covers all of them.
- Spanish, French and German captions switch from Apple's engine to Parakeet: about a third fewer word errors (E19);
  Italian and Portuguese too, about a quarter to two fifths fewer (#234, evidence `2026-10-30-parakeet-beats-apple-in-italian-and-portuguese`).
  `CaptionEngineFactory` and `EngineFallbackPolicy` stop assuming "Parakeet is English only".
- Parakeet's other 19 languages have no Apple engine to compare with and aren't in Seal's caption list yet (#234).
  Every win is a one-line change to the table.
- The Parakeet cases don't shrink. The levers (4-bit at 350 MB, 2-bit under #203) are accuracy choices for the owner.
- A new app extension target (StoreDownloaderExtension) and an App Group, plus pack packaging (`ba-package`) and
  upload in the release steps. Packs go through App Review.
- A fresh install with no network captions on Apple's engine, if its speech asset is already there, but has no
  speaker labels and no Parakeet until a network appears.
- 1.1 users updating get speaker labels as `prefetch`, and Parakeet at first launch if their caption language uses
  it. Until it lands, they use Apple's engine.
- No Seal server. Seal's privacy label is unchanged.
- Untested before building: loading a compiled Core ML model from an asset pack's URL, and cellular behaviour of
  pack downloads.
