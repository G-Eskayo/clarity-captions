# 0029 — Models download as packs; the base install is the app and Apple's engine

## Status

Proposed (2026-10-29, #200). Draft: the owner answers the `base`, `english-pack`, `speaker-pack`, `network-rule`,
`hosting` and `cellular` Decisions on the design PR first. If accepted, it supersedes [[0014]] decision 1 and
[[0025]] decisions 3 and 7 (models bundled, GitHub-hosted) for App Store and TestFlight builds. It amends
[[0001]]'s "on-device only" wording. Design: `docs/design/smallest-install-and-language-packs.md` §3–4.

## Context

- The 1.1 Release build is **765 MB**: Parakeet Ultra 498 MB, Sortformer 241 MB, and everything else 26 MB
  (`docs/perf/install-size-2026-10-29.md`). Every user pays for both models whatever language they caption in.
- The owner wants the smallest install that works, growing only when the user does something that needs more
  (#200).
- Apple-hosted asset packs (Background Assets, iOS/iPadOS/macOS 26.0+) download at install (`essential`), start at
  install and finish in the background (`prefetch`), or only when the app asks (`onDemand`). The app can track them
  and remove them, they update on their own schedule, and Apple hosts them free (200 GB per app). Citations in the
  design doc §4.
- Seal already captions without Parakeet: Apple's engine is the fallback when the model is missing ([[0025]] 2).
- Hebrew and Serbian need models Apple doesn't have (Hebrew research, 2026-10-29). Bundling every language
  would grow the app for everyone.

## Decision (proposed)

1. **The base install is the app** (code, every UI language, fonts; about 26 MB) **with Apple's speech engine**. It
   captions from the first launch.
2. **Every Seal model is a pack**: speaker labels (Sortformer), better English captions (Parakeet Ultra), and one
   per extra caption or translation language. Each pack is an Apple-hosted asset pack on Apple platforms and a Play
   Asset Delivery (or AI) pack on Android.
3. **Seal chooses which packs a device gets**, by the caption language and what the user turned on. It doesn't use
   the system's language-based picking, which needs iOS 27 and follows the UI language, not the caption language.
4. **Each pack carries `pack.json`**: id, kind, languages, minimum app build, sizes, per-file sha256 (the [[0025]]
   manifest as JSON) and its credit line. Seal verifies each pack version once before first use. A model that older
   builds can't load gets a **new pack id**, never a new version of the same one, because a live pack reaches every
   installed version.
5. **No model swaps mid-session.** A pack that lands or updates is used from the next Start.
6. **Debug, simulator and evaluation builds keep bundling** the models through the existing fetch scripts. One
   seam resolves bundle first, then packs.
7. **Settings > Downloads** lists Seal's packs with real sizes and Delete, plus what iOS keeps for Seal (speech and
   translation languages) without size or delete.
8. **"On-device only" is reworded** (CONTEXT.md, on acceptance):
   > Everything Seal does with sound and text runs on the device, with no network call while it runs. The models it
   > uses (Apple's speech and translation assets, and Seal's own packs) download once: at install, at first run, or
   > when the user adds a language or feature. They come only from Apple's servers, carry no user data, and after that
   > every feature works with no network. Losing the network never stops captions.

## Consequences

- The base drops from 765 MB to about 26 MB. A German speaker with speaker labels lands at about 267 MB. An English
  speaker with speaker labels stays at 765 MB unless the owner later picks the 4-bit or palettized builds.
- A new app extension target (StoreDownloaderExtension) and an App Group, plus pack packaging (`ba-package`) and
  upload in the release steps. Packs go through App Review.
- A fresh install with no network captions on Apple's engine, if its speech asset is already there, but has no
  speaker labels until a network appears.
- 1.1 users updating get the packs they already had as `prefetch` on update. Until they land, they use Apple's
  engine.
- No Seal server. Seal's privacy label is unchanged.
- Untested before building: loading a compiled Core ML model from an asset pack's URL, and cellular behaviour of
  pack downloads.
