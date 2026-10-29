# Smallest install, language packs, and the app in the phone's language (#200)

Design only, 2026-10-29. No app code changes until the owner answers the Decisions on the PR. Draft ADRs:
[0029](../adr/0029-models-download-as-packs.md) (models download as packs), [0030](../adr/0030-the-app-follows-the-phones-language.md)
(the app follows the phone's language), [0031](../adr/0031-translation-languages-the-user-keeps.md) (translation
languages the user keeps). Measurements: [`docs/perf/install-size-2026-10-29.md`](../perf/install-size-2026-10-29.md).

Builds on ADRs 0001, 0014, 0025, 0026, and on #35 (strings in catalogs), #37 (caption language), #53/#171
(translation), #60 (face to face).

## The owner's direction (2026-10-29, #200)

- **The app in the phone's language**: buttons, walkthrough, every screen, and Apple's own features (captions,
  translation) follow it, on every device that has the feature, and later on Android.
- **Smallest working install**: split the engines and everything else by use, so the smallest version that works
  gets onto the phone, and it grows only when the user does something that needs more.
- **Translation adds size only once bought and added.** The user can download, switch, change and delete the
  languages they translate between, and keep more than one. **At least one stays while translation is owned.**
- **As many languages as possible.** Hebrew first, Serbian a goal.

### The owner's revised answers (PR #205, 2026-10-29)

These replace the first answers to `base`, `english-pack` and `ui-text` where they differ:

- **Small install, then the best engine for the phone's language downloads by itself at first run.** No "better
  English" option anywhere: the best engine is the standard for every language and region. What gets skimmed is
  engines for languages the user doesn't use, so a Hebrew phone never downloads the English engine. Speaker labels
  download for everyone right after install.
- **Parakeet for every language it supports, not just English** (#158 measured it beating Apple in Spanish, French
  and German). Engines come in three groups: **Parakeet** for the ~25 European languages it covers, each measured
  before it switches; **Apple's built-in engines** (0 MB) where Parakeet doesn't reach; **Seal's own packs** where
  neither is good enough (Hebrew if it beats Apple, #201; Serbian, #204).
- **Every UI language still ships inside the app.** The App Store thins an app per device, never per language, and
  about 50 UI languages are about 0.6 MB against about 765 MB of models. Shipping them all also keeps iOS's per-app
  language switch working offline.

## Summary

1. **96.5% of today's app is two models.** The Release build is 765 MB: Parakeet Ultra 498 MB, Sortformer 241 MB,
   and everything else (code, strings, fonts) 26 MB. Strings are 12 KB per language. Only the models are worth
   splitting.
2. **Apple's own mechanism fits, from iOS 26.0, the app's current minimum.** Apple-hosted asset packs (Background
   Assets) download at install (`essential`), start at install and finish in the background (`prefetch`), or only
   when the app asks (`onDemand`). The app can track them and remove them. Apple hosts them for free (200 GB per app).
   Each pack updates on its own schedule, without an app update.
3. **The base:** the app plus Apple's speech engine, about 26 MB on disk (about 12 MB compressed). It captions
   from the first launch. Speaker labels (241 MB) then download for everyone, and **the best engine for the caption
   language downloads by itself at first run**: Parakeet (one 498 MB pack shared by all its languages) for English,
   Spanish, French and German today and for each further European language once it's measured; nothing for a
   language Apple's engine does best; a Seal pack where neither is good enough. Seal already captions on Apple's
   engine while a pack is missing (ADR 0025). Examples: English, Spanish, French or German phone 765 MB, Japanese
   phone 267 MB, Hebrew phone 267 MB on Apple's dictation engine (§3).
4. **UI text never downloads.** Every localization ships in the app, and the system picks the language: the
   per-app language if the user set one, otherwise the phone's language list. **Region never picks a language.**
   On a Hebrew or Arabic phone the whole app is mirrored and written in that language, while **each caption line
   runs in its own language's direction** (§2, right-to-left). Today a Hebrew phone gets the English app unmirrored,
   because there's no Hebrew localization yet; the pseudolanguage run shows SwiftUI mirrors most of it by itself, with
   a short list of fixes (bracket buttons, the caption area, selection, plurals).
5. **Translation languages:** Apple's are system-managed and shared. An app can check a pair but can't list or
   delete Apple's languages. Seal keeps its own list of the languages the user chose, enforces "at least one", and
   says plainly where iOS keeps the files. Seal's own packs (Hebrew captions, later Serbian) are deleted for real.
6. **ADR 0001's "on-device only" holds, with clearer wording.** Nothing in the captioning path ever uses the network.
   Models download once, from Apple only (Apple's speech and translation assets, or Seal's packs on Apple's App
   Store servers). That happens at install, at first run, or when the user adds something, and after that every
   feature works in airplane mode.

---

## 1. Today, measured

Release build, iPhone, 2026-10-29 (details and method in `docs/perf/install-size-2026-10-29.md`):

| Part | On disk | Compressed (zip, ≈ download) |
|---|---|---|
| Whole app (1.1 build 7) | **765.0 MB** | **716.9 MB** |
| Parakeet Ultra 6-bit (English captions today, ADR 0025) | 498.0 MB | 484.1 MB |
| Sortformer v2.1 fp16 (speaker labels, ADR 0014) | 240.6 MB | 220.4 MB |
| Everything else | 26.4 MB | 12.4 MB |
| English UI strings | 0.012 MB | |
| Apple's speech asset for the caption language | not in Seal's size (system storage, shared) | |
| Apple's translation languages | not in Seal's size (system storage, shared) | |

- Apple says Speech assets are "retained in system storage and [do] not increase the download or storage size of your
  application" ([WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/)). Translation models are "shared
  with all apps on the system, including the Translate app" ([WWDC24 10117](https://developer.apple.com/videos/play/wwdc2024/10117/)).
- We measured Apple's translation assets on the Mac at **155–291 MB per language**, including the shared family asset
  (#159, `docs/perf/translation-languages-results.md`). On a phone we can't read them, because they're outside the
  app's sandbox.
- The App Store's own figures are the per-device download and install sizes in App Store Connect
  ([Build Metadata, App File Sizes](https://developer.apple.com/help/app-store-connect/manage-builds/view-builds-and-metadata)).
  Ours are estimates from an unsigned build.
- Small finding: `latency-fixture.wav` (0.6 MB of test audio) ships in Release builds. Follow-up, not part of this
  design.

## 2. The app in the phone's language

### What the system already does

- **iOS / iPadOS:** an app's UI language comes from the user's preferred-language list and the localizations the app
  has (`Bundle.preferredLocalizations`,
  [docs](https://developer.apple.com/documentation/foundation/bundle/preferredlocalizations)).
- **Per-app language:** Settings shows a per-app Language picker once an app "support[s] multiple localizations, if the
  user has more than one language" in Language & Region. `UIPrefersShowingLanguageSettings` shows it always, and
  `UIApplication.openSettingsURLString` opens it ([WWDC24 10185](https://developer.apple.com/videos/play/wwdc2024/10185/),
  [openSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)).
- **macOS:** System Settings > General > Language & Region > Applications
  ([Mac User Guide](https://support.apple.com/guide/mac-help/change-the-system-language-mh26684/mac)).
- **`Locale.current`** reflects "any app-specific locale choice made in the Settings app"
  ([docs](https://developer.apple.com/documentation/foundation/locale/current)). `Locale.preferredLocales` (26.0+)
  takes per-app overrides into account, and `Locale.preferredLanguages`, which Seal uses today, "may be deprecated"
  ([docs](https://developer.apple.com/documentation/foundation/locale/preferredlocales),
  [WWDC25 222](https://developer.apple.com/videos/play/wwdc2025/222/)).
- **Android 13+** has the same model: `LocaleManager`, a `locale_config.xml`, and the system picker under
  Settings > Apps > (app) > Language, with AppCompat covering older versions
  ([docs](https://developer.android.com/guide/topics/resources/app-languages)).

### Proposed rule (ADR 0030)

| What | Follows | Fallback |
|---|---|---|
| UI text, walkthrough, every screen | the system's choice for Seal (per-app language, then the phone's list) | English |
| Caption language (first run) | the UI language, then down the phone's list, to the first one a caption engine here supports | ask (as #37 does) |
| Translation "Into" | the UI language if it differs from the caption language, else the next in the phone's list | first in Seal's kept list |
| Formats, and which variant comes first (es-MX vs es-ES) | region | |
| Which language | **never region** | |

- **Why not region:** Israel's region holds Hebrew, Arabic and Russian speakers. A Russian speaker in Israel gets
  Hebrew screens by region and Russian screens by language. The phone's language is the one the person picked.
- **Seal adds no UI-language setting of its own** ([[0013]]). A "Language" row in Settings opens the system's per-app
  page. That row only shows once Seal ships a second localization (#38, Spanish).
- **All UI localizations ship in the app** (owner, kept 2026-10-29). About 12 KB per language means about 50
  languages cost about 0.6 MB, against a 26 MB base and about 765 MB of models. The App Store thins an app per
  device, and Apple's size docs describe only device variants, with nothing on slicing by language, so there's no
  store setting that ships only one language's text ([Reducing your app's size](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size);
  evidence `2026-10-29-app-thinning-is-per-device-not-per-language`). A
  language pack for text would add a download, a failure mode and a blank-screen risk to save nothing, and iOS's
  per-app language switch would stop working offline.
- **Apple's own features in that language:** captions and translation take explicit locales
  ([SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber),
  [TranslationSession](https://developer.apple.com/documentation/translation/translationsession)), so Seal passes them
  the caption and Into languages chosen above. They don't follow the per-app language by themselves (no doc ties
  them to it). *Unverified:* whether Apple's system sheets inside Seal (Translation's download sheet, the microphone
  prompt) follow Seal's per-app language or the phone's.

### What it needs from the code (later, not now)

- `CaptionLanguageCenter` and `TranslationCenter` read `Locale.preferredLanguages`. They move to
  `Locale.preferredLocales` with `Bundle.main.preferredLocalizations.first` put first, so a per-app choice wins.
- `CaptionLanguage.resolve` stays pure and gains a "UI language first" test.

### Right-to-left: the mirrored app (owner, #200, 2026-10-29 18:56)

**The owner's rule.** A phone in Hebrew, Arabic or another right-to-left language gets the mirrored app: the layout
flips and every word is in that language, written to make sense in it, not word for word. **Caption direction follows
the caption language, not the phone's.** Hebrew captions run right to left in an English app, and English captions
run left to right in a Hebrew app. In face to face (#60, #208), each half follows its own language.

**What happens today** (iPhone 17 simulator, iOS 26, Debug build of `c04a131`, screenshots on PR #205, evidence `2026-10-29-seal-on-a-right-to-left-phone`):

- **With `-AppleLanguages (he)`, nothing flips.** Seal has one localization, English, so iOS runs it in English, left
  to right. Only the region formats change: with `-AppleLocale he_IL` the saved list shows "Today, 8:56" and
  "Yesterday, 19:12" in 24-hour time. **The mirrored app needs the Hebrew localization itself** (strings, and `he` in
  the project's known regions). There's no switch to turn on.
- **With Xcode's right-to-left pseudolanguage** (`-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`),
  SwiftUI mirrors almost everything by itself: the gear and the saved-list icon swap sides, `list.bullet` mirrors,
  Settings rows and the color swatches reverse, page headers move "‹ Settings" to the right, Stop moves to the bottom
  left, "Skip tour" moves left, and the tour's spotlights follow the moved controls. That matches the owner's check:
  no hard-coded `.left`/`.right` anywhere in `Apps/Spike/Sources`.
- **What's wrong in the pseudolanguage run** (each with file:line in the audit below):
  - The bracket buttons break: `[ Delete all ]` shows as `]Delete all [`, and the same for `[ Save ]`, `[ New ]`,
    `[ Next › ]` and `[ Done ]`.
  - English captions are right-aligned, because the caption area follows the app's direction. Under the owner's
    rule they stay left to right.
  - The text chevrons ("‹ Settings", "Full license texts ›", "Next ›", "‹ Back") keep pointing the English way.
    With real Hebrew strings the Unicode bidi algorithm should mirror ‹ and › by itself (both are Bidi_Mirrored).
    To check once Hebrew strings exist.
  - The launch seal and its speed lines are drawn on a `Canvas` and don't mirror. That may be right (it's a picture,
    not a direction), so it's a Decision.

**Proposed rule (ADR 0030, points 7–10):**

| What | Direction comes from |
|---|---|
| Screens, walkthrough, Settings, page headers, buttons | the UI language (SwiftUI's `layoutDirection`, set by iOS) |
| A caption line, live or saved, and its speaker label | **the caption language**: `Locale.Language.characterDirection` of the engine's locale |
| A translation line | **the Into language** |
| Each half in face to face | its own language. A half that shows a translation on top and what was said underneath has one line in each language's direction |
| Text nobody can predict (a name someone typed, a mixed-language line) | the text's own first strong character (Unicode bidi) |
| Numbers, dates, times | the locale's formats: region decides 12/24 hours, the UI language decides the words |
| Pictures (the seal, the Listening light) | not mirrored, unless the owner chooses otherwise (Decision `rtl-seal`) |

- **Mechanism, later:** the caption area sets `.environment(\.layoutDirection, …)` from the caption language on its
  `LazyVStack`, so `.leading` means "where this language starts" there, and each translation line sets its own. One
  pure function in CaptionCore decides the direction from a language, with tests for he, ar, fa, ur, en, es and a
  mixed line.
- **Translated by meaning, not by word** (#38's native-speaker rule): each RTL localization is reviewed by a native
  speaker on the running app, with screenshots, before it ships. The bracket buttons, "Speaker 1", "Today, %@" and the
  tour's "3 of 4" each need their own wording in Hebrew and Arabic, not a copied pattern.
- **Plurals.** Hebrew has a dual and Arabic has six plural categories. Today every counted string goes through
  `String(format:)` and the catalog has no plural variants, so "%lld conversations" has one form for every number.
  Counted strings move to `String(localized:)` with interpolation and plural variants in `Localizable.xcstrings`.
- **Digits.** Formatted numbers follow the locale (Arabic-Indic digits where the user's locale uses them).
  `String(format:)` always writes Western digits, a second reason to move off it.
- **Proof, per the PR rules:** every RTL ticket carries screenshots of every screen in the real language and in the
  pseudolanguage. Face to face only appears on iPad and the unfolded Duo, so its RTL proof is an iPad screenshot.

### Audit: what doesn't mirror by itself today

Grepped on `c04a131` (main at `4b6c5ad` plus this design; no app code differs from main). "Flips" means SwiftUI
already handles it.

**Directional icons and animations**

| Where | What | In the RTL run |
|---|---|---|
| `Apps/Spike/Sources/OneScreenPieces.swift:98`, `:105` | `RetroWords`: `Text("[ ")`, the word, `Text(" ]")` in an `HStack` | **Broken**: the HStack swaps the brackets, so `[ Save ]` shows `]Save [` (every bracket button) |
| `Apps/Spike/Sources/OneScreenPieces.swift:150` | page header `"‹ \(backTitle)"` | moves right, but the chevron still points left; Hebrew text should mirror it by bidi (unverified) |
| `Apps/Spike/Sources/AboutCreditsView.swift:35` | `"Full license texts" + " ›"` | chevron still points right; same bidi caveat |
| `Apps/Spike/Sources/SettingsPage.swift:182`, `:272` | a lone `Text(verbatim: "›")` on the caption-language and translation rows | a lone neutral glyph takes the row's direction; to check on a Hebrew screen |
| `Apps/Spike/Sources/SettingsPage.swift:424` | `"%lld conversations" + " ›"` (TestFlight builds only) | as above |
| `Apps/Spike/Sources/SettingsPage.swift:336`–`:337` | `A−` then `A+` in an HStack | flips: A+ ends up on the left. Decision `rtl-size` |
| `Apps/Spike/Sources/ContentView.swift:740`, `:811` | `gearshape`, `list.bullet` | flips correctly (`list.bullet` mirrors; the gear is symmetric) |
| `Apps/Spike/Sources/ContentView.swift:905`, `FaceToFaceView.swift:68` | `translate` mark before a translation | moves with the app; should follow the translation's language |
| `Apps/Spike/Sources/MorphingControl.swift:61` | ✕ rotates in from −90° | symmetric, fine |
| `Apps/Spike/Sources/ContentView.swift:802` | compact Stop at `.trailing` | flips to the bottom left, as a mirrored app should |
| `Apps/Spike/Sources/LaunchOverlay.swift:180`, `:209`–`:216`, `:246`–`:330` | the seal, its flippers and the speed lines behind it, drawn on a `Canvas` at fixed x | **not mirrored** (a Canvas never is). Decision `rtl-seal` |

**Walkthrough arrows and coach marks**

| Where | What | In the RTL run |
|---|---|---|
| `Apps/Spike/Sources/TourOverlay.swift:191` | `[ Next › ]` | brackets broken (above); the chevron points the English way |
| `Apps/Spike/Sources/TourOverlay.swift:207`–`:214` | "3 of 4 · ‹ Back" | the row reverses to "‹ Back · 4 of 4"; the chevron should point right |
| `Packages/CaptionCore/Sources/CaptionCore/HowToUseTour.swift:87`–`:90` | "\(number) of \(total)" | needs Hebrew and Arabic wording |
| `Apps/Spike/Sources/TourOverlay.swift:56`–`:133` | spotlights and the touch hole, from anchors | **follow the mirrored controls** (tour step 1 and 4 screenshots). The tour draws no arrows |
| `Apps/Spike/Sources/TourOverlay.swift:73`–`:75` | Skip tour at `.trailing` | flips to the left, fine |

**The caption area**

| Where | What | In the RTL run |
|---|---|---|
| `Apps/Spike/Sources/ContentView.swift:882`, `:886`, `:924` | live caption list, `.leading` | follows the **app's** direction: English captions right-aligned in a Hebrew app, and Hebrew captions would be left-aligned in an English app |
| `Apps/Spike/Sources/ContentView.swift:900`–`:910` | translation on top, what was said underneath | two languages in one block; each line needs its own direction |
| `Apps/Spike/Sources/FaceToFaceView.swift:44`, `:65`, `:80` | each face-to-face half, `.leading` | as the live list, per half and per line |
| `Apps/Spike/Sources/SavedTranscriptText.swift:31`, `:41` | a saved conversation's words | as the live list; a saved conversation needs its caption language stored with it |
| `Apps/Spike/Sources/SavedConversationsView.swift:82`–`:91` | saved-list snippets, `.multilineTextAlignment(.leading)` | follow the app; a Hebrew snippet in an English app would be left-aligned |
| `Apps/Spike/Sources/CaptionTextSelection.swift:27`–`:40` | selection: glyphs sorted by `minX`; "leading" = `minX`, "trailing" = `maxX` | **assumes left-to-right text**: in Hebrew captions the handles and hit-testing go to the wrong end |
| `Apps/Spike/Sources/ContentView.swift:1429`–`:1446`, `SavedTranscriptText.swift:111`–`:128` | caret and handle positions | same assumption |
| `Packages/CaptionCore/Sources/CaptionCore/TranscriptExport.swift:16`, `:41` | shared transcript: `"Speaker \(n): "` | hard-coded English; a Hebrew line after an English label needs a direction mark (U+200F) or it reorders |

**Numbers and times**

| Where | What | In the RTL run |
|---|---|---|
| `Apps/Spike/Sources/SavedConversationsView.swift:260`–`:265` | `date.formatted(...)` inside "Today, %@" | **works**: he_IL gave 24-hour times; only the words need translating |
| `Apps/Spike/Sources/SavedConversationsView.swift:100`, `SettingsPage.swift:424`, `BetaFeedbackViews.swift:219` | `String(format: "%lld conversations…")` | no plural variants; always Western digits |
| `Packages/CaptionCore/Sources/CaptionCore/MainScreen.swift:68` | "No one talked for \(minutes) minutes" | no plural variants in the catalog |
| `Apps/Spike/Sources/CaptionLanguagePage.swift:238` | "Downloading %@ · %lld%%" | Western digits and a fixed `%` (Arabic uses ٪, placed per locale) |
| `Apps/Spike/Sources/ContentView.swift:1508` | "Speaker \(sp + 1)" | localizable; needs its own wording |
| `Apps/Spike/Sources/SavedConversationsView.swift:29` | "Kept for 30 days, then deleted." | number inside the string; fine once translated |

**Not checked:** the selection screen and the first-run microphone screens in RTL (their demo flags run the real
launch, which this build couldn't finish without the models; see the PR), and face to face (iPad only).

## 3. What's in the base install

### The pieces, by who needs them

| Piece | Who needs it | Size | Today | Proposed |
|---|---|---|---|---|
| App (code, all UI languages, fonts) | everyone | 26.4 MB | in the app | in the app |
| Apple's caption engines (SpeechTranscriber, DictationTranscriber) + the locale's asset | everyone (fallback); languages where Apple is the best engine | 0 MB to Seal | system download at first run | same |
| **Speaker labels** (Sortformer) | everyone | 240.6 MB | in the app | **pack, `prefetch`: right after install** |
| **Parakeet** (Parakeet Ultra, one pack for all its languages) | anyone whose caption language Parakeet wins (§6: en, es, fr, de today) | 498.0 MB | in the app | **pack, requested at first run for that language** |
| Seal's own caption packs (Hebrew if it beats Apple, #201; Serbian, #204) | that language only | ~200–500 MB each (est.) | none | **pack, requested at first run for that language** |
| Apple's translation languages | translation owners | 0 MB to Seal (155–291 MB to the system, Mac) | system | same |
| Seal's own translation packs (languages Apple lacks) | translation owners, that pair | unknown | none | **pack, on demand, only if owned** |

### Size per person, today vs proposed

Base 26 MB + speaker labels 241 MB for everyone + the one engine the caption language needs (§6):

| Person (caption language from the phone, ADR 0030) | Engine | Today | Proposed (on disk) |
|---|---|---|---|
| Install, before anything downloads | Apple's | 765 MB | **26 MB** |
| After speaker labels land, before first run | Apple's | 765 MB | 267 MB |
| English phone (Mom's case) | Parakeet | 765 MB | 765 MB (26 + 241 + 498) |
| Spanish, French or German phone | Parakeet (#158) | 765 MB (Parakeet unused) | 765 MB, Parakeet now used |
| English and German both (face to face, or switching) | Parakeet, one pack | 765 MB | 765 MB: the second language costs nothing |
| Italian, Polish or another Parakeet language not yet measured | Apple's until measured, if Apple has it | 765 MB | 267 MB, then 765 MB once Parakeet wins (§6) |
| Japanese, Korean, Chinese phone (Parakeet doesn't cover them) | Apple's | 765 MB | **267 MB** |
| Hebrew phone, Apple's DictationTranscriber (Decision `hebrew-first`) | Apple's | n/a | **267 MB** |
| Hebrew phone, if a Seal Hebrew pack beats Apple (#201; 2-bit, speculative) | Seal's | n/a | ≈ 470–510 MB |
| Serbian phone (#204) | Seal's | n/a | 267 MB + the Serbian pack (unknown) |
| + translation into Spanish (Apple) | | system +286 MB (Mac figure) | same; not Seal's |

The English, Spanish, French and German cases don't shrink, because their best engine is the big one, and the owner
wants the best engine as the standard. What the packs remove is engines nobody uses: a Japanese or Hebrew phone stops
carrying 498 MB of European Parakeet. Two levers would shrink the Parakeet cases too. Both are owner choices on
accuracy (Decision `shrink`), and #203 is measuring smaller still:

- the 4-bit Parakeet build: 350 MB (320 MB zipped), 14.8% vs 13.8% English WER (ADR 0025, E12), still well ahead of
  Apple's 17.2%
- palettized Sortformer: about 97 MB, about 0.9 points worse diarization error (ADR 0014)

### First run with a 26 MB base

1. Install: about 12 MB from the App Store. Speaker labels are a `prefetch` pack: they start downloading with the
   install and finish in the background (Decision `speaker-pack`).
2. First launch: Seal settles the caption language from the phone's language (ADR 0030 point 3) and picks the best
   engine for it (§6). The existing first-run step installs Apple's speech asset for that language (system, shared).
   **Captions work from here**, on Apple's engine.
3. In the same first launch, Seal requests the engine pack that language needs, if any (Parakeet, or a Seal
   language pack) as `onDemand`, with no question asked: it's the standard engine, not an option. A plain line shows
   the progress ("Getting the best captions for German · 41%"). No new first-run screen ([[0013]]). Big downloads
   follow the `cellular` rule.
4. When a pack lands, it's checked (§4), and the next Start uses it. A running session is never swapped mid-way.
   - Parakeet already compiles for the phone on first load (35 s on a Mac, ADR 0025), so that step moves from
     first run to the first Start after the pack arrives, with the same status line.
   - Until the pack is there, Apple's engine captions, exactly like today's fallback.
5. Nothing after step 3 needs the network again, unless the user picks a caption language whose engine isn't on the
   phone. Then that engine downloads the same way, and Apple's engine captions meanwhile.

**Why not at install?** On iOS 26 the App Store can't pick a pack by language: `essential` and `prefetch` packs go to
every device, and *localized* packs (picked by the app's language) need iOS 27 (§4). A Parakeet `prefetch` would put
498 MB on every Japanese and Hebrew phone. So Seal asks for the engine at first launch. On iOS 27 a localized
`prefetch` pack could start it during install for phones whose UI language is one Parakeet wins; that's an
optimisation for later, since the caption language can differ from the UI language.

### Squaring this with ADR 0001 "on-device only"

ADR 0001 and CONTEXT.md already allow one exception: Apple's speech asset "may require a one-time network fetch
before first use". Seal's packs are the same kind of thing. The proposed wording (ADR 0029, to replace CONTEXT.md's
*On-device only* once approved):

> **On-device only**: everything Seal does with sound and text (capture, captions, speaker labels, sound labels,
> translation) runs on the device, with no network call while it runs. The models it uses (Apple's speech and
> translation assets, and Seal's own packs) download once: at install, at first run, or when the user adds a language
> or feature. They come only from Apple's servers, carry no user data, and after that every feature works with no
> network. Losing the network never stops captions. The worst case is waiting for a model before a feature first
> works.

What stays true: no Seal server, no user data leaves the phone, the privacy label stays "Data Not Collected"
(Apple-hosted packs come from Apple's App Store infrastructure, the same as the app). What changes: a fresh install
in airplane mode captions on Apple's engine (if its asset is there) but has no speaker labels until a network
appears. Today that install has everything.

## 4. The pack mechanism

### iOS, iPadOS, macOS: Apple-hosted asset packs (Background Assets)

The facts it rests on, each from Apple's current docs:

| Fact | Source |
|---|---|
| Managed packs (`AssetPackManager`, `AssetPack`) are iOS/iPadOS/macOS 26.0+. Seal's minimum is 26.0 | [AssetPackManager](https://developer.apple.com/documentation/backgroundassets/assetpackmanager), [overview](https://developer.apple.com/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs) |
| Apple hosting works on every platform except watchOS, for apps distributed through TestFlight and the App Store | [Downloading Apple-hosted asset packs](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs), [overview](https://developer.apple.com/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs) |
| `essential`: "Downloads the asset pack as part of the app's installation process", shown in the App Store's install progress. `prefetch`: "during the app's installation process, but lets it continue in the background after installation finishes". `onDemand`: "only when you explicitly use an API to request" it. Essential and prefetch can apply on first install, on update, or both | [Creating managed asset packs](https://developer.apple.com/documentation/backgroundassets/creating-managed-asset-packs) |
| Even an essential pack can be missing at launch ("network dropouts or other uncommon issues"), so the app calls `ensureLocalAvailability` before use | [Downloading Apple-hosted asset packs](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs) |
| The App Store's "Up to" size includes essential packs. Prefetch and on-demand aren't listed in it (*inferred*) | [Asset pack size limits](https://developer.apple.com/help/app-store-connect/reference/apple-hosted-asset-pack-size-limits) |
| 200 GB and 200 packs per app record, included in the Developer Program membership. No per-pack limit published | [Size limits](https://developer.apple.com/help/app-store-connect/reference/apple-hosted-asset-pack-size-limits), [WWDC25 325](https://developer.apple.com/videos/play/wwdc2025/325/) |
| Packs upload separately from builds and aren't tied to one. A new live version **replaces the old one for every installed app version**. The system keeps them up to date in the background, and packs go through App Review | [WWDC25 325](https://developer.apple.com/videos/play/wwdc2025/325/), [`checkForUpdates()`](https://developer.apple.com/documentation/backgroundassets/assetpackmanager/checkforupdates()) |
| `remove(assetPackWithID:)` "Removes the specified asset pack from the device". The system won't remove packs on its own while the app is installed. Pack storage shows in the iOS storage view | [remove](https://developer.apple.com/documentation/backgroundassets/assetpackmanager/remove(assetpackwithid:)), [Downloading…](https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs) |
| Progress through `statusUpdates(forAssetPackWithID:)`. `AssetPack` gives `downloadSize`, `version` and `language` | [AssetPackManager](https://developer.apple.com/documentation/backgroundassets/assetpackmanager), [AssetPack](https://developer.apple.com/documentation/backgroundassets/assetpack) |
| Needs a `StoreDownloaderExtension` app extension, an App Group, and `BAHasManagedAssetPacks` / `BAUsesAppleHosting` / `BAAppGroupID` in Info.plist | [AssetPackManager](https://developer.apple.com/documentation/backgroundassets/assetpackmanager), [StoreDownloaderExtension](https://developer.apple.com/documentation/storekit/storedownloaderextension) |
| Files come out of `url(for:)` (don't keep the URL past the process, don't call it on the main thread), `contents(at:)` or `descriptor(for:)`. All packs share one namespace. ML models are a supported asset type | [url(for:)](https://developer.apple.com/documentation/backgroundassets/assetpackmanager/url(for:)) |
| Packs are built with `xcrun ba-package` and tested with the `ba-serve` mock server | [WWDC25 325](https://developer.apple.com/videos/play/wwdc2025/325/) |
| *Localized* packs (picked by the phone's or app's language) are iOS/macOS 27+ only. Devices on 26 don't get them | [Localized asset packs](https://developer.apple.com/documentation/backgroundassets/reducing-download-and-storage-demands-with-localized-asset-packs), [WWDC26 378](https://developer.apple.com/videos/play/wwdc2026/378/) |
| On-Demand Resources (the old mechanism) is deprecated as of iOS 27 | [ODR size limits](https://developer.apple.com/help/app-store-connect/reference/on-demand-resources-size-limits/), [NSBundleResourceRequest](https://developer.apple.com/documentation/foundation/nsbundleresourcerequest) |
| Not found in Apple's docs: whether pack downloads respect the cellular setting, and whether Apple signs packs (only "HTTPS for all downloads") | **Unconfirmed** |

Design choices that follow from those facts:

- **Seal picks its own packs, not the system.** Localized packs need iOS 27. Seal supports 26, and its packs follow
  the *caption* language, which can differ from the phone's. Speaker labels are `prefetch` (everyone gets them).
  Engine packs are `onDemand`, and Seal requests the one the caption language needs at first launch (§3).
- **Pack IDs carry a format version** (`speech-parakeet-ultra-pal6-v1`, `diarizer-sortformer-v2_1-fp16-v1`). A
  live pack replaces the old one for every installed app version, so a model the old app can't load must get a new
  ID, never a new version of the same ID.
- **Seal still checks every file itself** (ADR 0025's sha256 pattern, §4.3), because Apple documents no integrity
  check. It checks once per pack version, after download and before first use, and records the result. Hashing
  498 MB at every launch would cost seconds.
- **Updates never swap a model mid-session.** Seal resolves the pack URL when an engine is built, at Start.
- **Debug and simulator builds keep bundling** through the existing fetch scripts, so screenshots, tests and the
  Mini's EngineEval work offline. One `ModelPacks` seam looks in the bundle first, then in `AssetPackManager`. Only
  App Store and TestFlight builds drop the bundled copies. The mock server (`ba-serve`) is for the pack-download
  tests themselves.
- **Updating from 1.1:** the update that drops the bundled models must not leave English users on the weaker
  engine for long. Speaker labels are `prefetch` on first install and on `subsequentUpdate`. Parakeet can't be
  `prefetch` on update without going to every 1.1 user, so Seal requests it at the first launch after the update
  when the caption language uses it, and Apple's engine covers the gap. (Every 1.1 user has Parakeet in the app
  today, so a `prefetch` on update only would keep their size as it is and avoid the gap. Decision `update-path`.)

### Android: Play Asset Delivery (when there's an Android app, #43)

| Fact | Source |
|---|---|
| Asset packs come in three modes. **install-time** ships with the install and counts toward the store's size. **fast-follow** downloads right after install, even if the app isn't opened. **on-demand** downloads while the app runs | [Play Asset Delivery](https://developer.android.com/guide/playcore/asset-delivery) |
| Pack updates come only with an app update (an update "invalidates" downloaded fast-follow and on-demand packs, and Play patches them). Unlike Apple, a pack can't update on its own | [Play Asset Delivery](https://developer.android.com/guide/playcore/asset-delivery) |
| Limits: 1.5 GB per asset pack, up to 100 packs, 30 GB in total for on-demand plus fast-follow. Over 200 MB, Play warns users on mobile data. All limits are compressed sizes (*another version of the page shows a 200 MB base and 4 GB; plan for the smaller*) | [Play Console Help 9859372](https://support.google.com/googleplay/android-developer/answer/9859372) |
| `AssetPackManager`: `fetch`, `getPackStates` (size before download), `getPackLocation`, `removePack`. Downloads over 200 MB wait for Wi-Fi unless the app shows Play's confirmation dialog | [Integrate (Java)](https://developer.android.com/guide/playcore/asset-delivery/integrate-java) |
| **Play for On-device AI** (beta) adds "AI packs" for models, with targeting by device model, chip and RAM, up to 1.5 GB each | [Play for On-device AI](https://developer.android.com/google/play/on-device-ai) |
| ML Kit on-device translation: 59 languages including Hebrew (no Serbian), "around 30MB" per model, with `getDownloadedModels`, `download(…requireWifi())` and `deleteDownloadedModel`. Non-English pairs pivot through English | [Translation](https://developers.google.com/ml-kit/language/translation/android), [language list](https://developers.google.com/ml-kit/language/translation/translation-language-support), [overview](https://developers.google.com/ml-kit/language/translation) |
| On-device `SpeechRecognizer` (API 31+) can list languages and `triggerModelDownload` (API 33+), but has no delete | [SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer), [RecognitionSupport](https://developer.android.com/reference/android/speech/RecognitionSupport) |

Mapping: Apple `onDemand` → PAD on-demand. `prefetch` → fast-follow. `essential` → install-time. Seal's Settings
screen works the same on both. On Android, ML Kit translation models are listable and deletable, so delete is real
there too. Leaning, not decided: AI packs once they leave beta, for per-device model choice (e.g. 4-bit on low-RAM
phones).

### Shared: the pack manifest

Each pack carries `pack.json` at its root, read by both platforms:

```json
{
  "id": "speech-he-parakeet-he-pal2-v1",
  "kind": "speech",
  "languages": ["he-IL"],
  "engine": "parakeet-tdt",
  "minAppBuild": 9,
  "sizeOnDisk": 212000000,
  "files": [{ "path": "Encoder.mlmodelc/weights/weight.bin", "size": 198000000, "sha256": "…" }],
  "credit": "Hebrew Parakeet by …, CC BY 4.0, from NVIDIA Parakeet TDT 0.6B v3; compressed for Seal Speak"
}
```

- `files` is today's `scripts/models/*.sha256` (ADR 0025) as JSON. The repo keeps it, and the same script writes it
  for the build-time bundle and for `ba-package`.
- `kind` is `speech`, `diarizer` or `translation`. `languages` drives what the language lists offer, and `credit`
  feeds the credits screen and NOTICE.md (licence per pack, Hebrew research T9).
- An app build below `minAppBuild` ignores the pack, so a newer model never breaks an older app.

### Storage in Settings

One Settings page, **Downloads**, plain words, no engine names ([[0013]]):

- **Seal's packs:** "Speaker labels: 241 MB. Delete". "Captions for English, Spanish, French, German: 498 MB".
  "Hebrew captions: 212 MB". Each row shows real size from the manifest, plus progress while it downloads. There's
  no "better captions" pack to opt into: an engine row names the languages it captions.
  - **The engine for the caption language has no Delete** (the owner: the best engine is the standard, not an
    option). It gets one once no language the user keeps needs it, e.g. after switching captions from German to
    Japanese (Decision `unused-engine`).
  - Deleting says what changes ("Captions keep working; Speaker 1 / Speaker 2 stop until you download it again").
  - A pack in use by a running session can't be deleted until Stop.
- **Kept by iOS:** the caption language's speech asset and the translation languages are listed as "Kept by iOS,
  shared with other apps", with no size (we can't read it) and no delete (§5).

## 5. Translation: Apple's languages and Seal's own

| | Apple Translation | Seal's own translation packs (future) |
|---|---|---|
| Who manages the files | the system, shared with every app ([WWDC24 10117](https://developer.apple.com/videos/play/wwdc2024/10117/)) | Seal (asset pack) |
| Can Seal list what's downloaded? | **No.** Seal can only ask about a pair: `status(from:to:)` → installed / supported / unsupported ([LanguageAvailability](https://developer.apple.com/documentation/translation/languageavailability)) | yes |
| Can Seal download? | yes, through Apple's own sheet (`prepareTranslation()`, [TranslationSession](https://developer.apple.com/documentation/translation/translationsession)) | yes |
| Can Seal delete? | **No API.** The user deletes in Settings > Apps > Translate > Downloaded Languages (Apple's developer doc; the iOS 27 guide calls it "Languages"), or on Mac in System Settings > General > Language & Region > Translation Languages ([Translating text](https://developer.apple.com/documentation/translation/translating-text-within-your-app), [iPhone guide](https://support.apple.com/guide/iphone/change-your-translate-settings-iphddb6e7264/ios)) | yes, `remove(assetPackWithID:)` |
| Size known to Seal? | no | yes |

### The one list (ADR 0031)

Once translation is bought, Settings > Translation shows **Your languages**, Seal's own saved list:

- **Add:** pick from every language Apple or a Seal pack can translate the caption language into. Adding an Apple
  language opens Apple's download sheet. Adding a Seal pack downloads it with progress. Adding is the only step that
  uses space.
- **Switch:** tap a language to translate into it. Kept languages switch instantly, with no download.
- **Delete:**
  - A Seal pack deletes for real.
  - An Apple language comes off Seal's list, and one plain line says "iOS keeps this language for other apps too. To
    free its space: Settings › Apps › Translate."
  - Seal can't open that page itself. `openSettingsURLString` opens only Seal's own page.
- **At least one:** while translation is owned, the last language in the list has no Delete. The first language is
  the default Into language (§2), downloaded when translation is bought.
- **Pairs:** a translation needs both sides on the device (the caption language and the Into language). Seal shows
  one row per Into language and handles the pair underneath. Face to face (#60) uses the same list both ways.

## 6. Which languages each engine covers

| Engine | Where | Count | English | Spanish | German | Hebrew | Arabic | Russian | Serbian | Source |
|---|---|---|---|---|---|---|---|---|---|---|
| Apple SpeechTranscriber | macOS 26.5.1 (Mini) | 30 locales / 10 languages | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | our probe, 2026-10-29 |
| Apple SpeechTranscriber | macOS 27.0.1 (owner's laptop) | 45 locales | | | | ✗ | | | | #200 |
| Apple DictationTranscriber | macOS 26.5.1 | 54 locales / 33 languages | ✓ | ✓ | ✓ | **✓ he-IL** | ✓ ar-SA | ✓ | ✗ | our probe |
| Apple Translation | macOS 26.5.1 | 38 ids / 22 languages | ✓ | ✓ | ✓ | **✗** | ✓ | ✓ | ✗ | our probe |
| Apple Translation | macOS 27.0.1 | 47 | | | | **✓ he↔en** | | | | #200 |
| Parakeet TDT 0.6B v3 (Ultra's base) | any | 25 European languages | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ (Croatian ✓) | [model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| ML Kit translation (Android) | Android | 59 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | [list](https://developers.google.com/ml-kit/language/translation/translation-language-support) |

- **Not checked on iOS 26 or 27.** There's no phone on the Mini, and the iOS Simulator reports every Translation pair
  as unsupported. Apple's lists vary by device (`supportedLocales` "is empty if the device is unsupported";
  `maximumReservedLocales` "may vary between devices according to storage space"):
  [SpeechTranscriber.supportedLocales](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocales),
  [maximumReservedLocales](https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales).
  The app already reads the lists on the device (E27). One follow-up runs the same probe on an iPhone on 26 and on 27.
- **Hebrew captions cost 0 MB today if Seal adds DictationTranscriber.** It uses the same models as system
  dictation ([DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)). Its
  Hebrew accuracy has never been measured (Hebrew research T1). Seal's own Hebrew pack is worth its size only if it
  beats that.
- **Hebrew translation needs OS 27** on Apple's side.
- **Serbian has no on-device engine anywhere in this table.** It needs a Seal caption pack. Parakeet v3 has
  Croatian, a close relative, but that's a *guess*, not a measurement. It also needs a Seal translation pack, and
  licence and model are unresearched (ADR 0026 rule 4: no CC BY-NC).
- Parakeet covers 24 more European languages than Seal uses it for (English only today). Spanish, French and German
  are measured (#158: Parakeet wins all three). The other 21 each get the same test before they switch.

### The best engine for each language: three groups (owner, 2026-10-29)

Seal picks one engine per caption language. Nobody chooses it in Settings ([[0013]]), and there's no "better" tier:

| Group | Languages | Size to Seal | When it's the engine |
|---|---|---|---|
| **Parakeet** (Parakeet Ultra) | the 25 European languages it covers | 498 MB, once, for all of them | the language passed #158's test: Parakeet's 95% interval reaches Apple's WER or below, and the better engine is at 15% WER or under (ADR 0026 §3). Today: **en, es, fr, de** |
| **Apple's built-in engines** (SpeechTranscriber, else DictationTranscriber) | every language Apple has where Parakeet doesn't reach or doesn't win | 0 MB (system, shared) | Parakeet doesn't cover it (ja, ko, zh, he, ar, …), or covers it but lost or isn't measured yet |
| **Seal's own packs** | languages where neither is good enough | ~200–500 MB per language (est.) | Apple has nothing, or the best of Apple and Parakeet is above 15% WER, and a Seal model measured better: Hebrew if it beats Apple (#201), Serbian (#204) |

- **A Parakeet language not measured yet** stays on Apple's engine if Apple has it. The owner's rule is "each
  measured before it switches". If Apple has no engine at all for it, the language isn't offered until Parakeet is
  measured on it (Decision `parakeet-unmeasured`).
- **Measuring one language** is #158's harness (`scripts/engine-eval`, FLEURS test split, the same rule). FLEURS has
  all 25 Parakeet languages (the model card reports all 25 on it, E14), so measuring the other 21 is a run, not a project.
- **Where the table lives:** in the app, as a CaptionCore value (language → engine), shipped with app updates and
  under unit tests. Not in `pack.json`: changing a live pack sends every installed copy a new version, and Apple's
  docs don't say a metadata change avoids re-downloading 498 MB.
- **"Configured to the language on download"** (the owner's question on the first answers): Parakeet v3 and Ultra
  have no language setting. They detect the language from the audio, and FluidAudio's Parakeet v3 path takes no
  language argument (checked in the FluidAudio checkout, 2026-10-29). Seal still knows the caption language: it picks
  the engine, the text direction (§2) and the fallback. A German speaker who drops into English gets English words,
  which is what face to face (#60) already relies on.

### Parakeet: one shared pack, not one per language

**One pack.** Parakeet Ultra is one model for all 25 languages: one encoder (about 461 of its 498 MB), one decoder
and joint network, and one shared vocabulary (E14; evidence `2026-10-29-parakeet-is-one-pack-for-all-its-languages`). There's no per-language part to split off, so a "German Parakeet
pack" would be the same 498 MB as the English one.

| Pack | Covers | On disk | Download (zip -9 estimate) | Source |
|---|---|---|---|---|
| Parakeet Ultra 6-bit (today's, ADR 0025) | all 25, used for en, es, fr, de | 498.0 MB | 484.1 MB | `docs/perf/install-size-2026-10-29.md` |
| Parakeet Ultra 4-bit (Decision `shrink`) | the same | 350 MB | 320 MB | E12 |
| A per-language pack (e.g. Seal Hebrew, #201) | one language | est. 200–500 MB | | Hebrew research, speculative |

- **Per-language packs only exist where the model is per-language:** Seal's own fine-tunes (Hebrew, Serbian), or
  single-language models like FluidAudio's Japanese Parakeet. Each is a full model, so two such languages cost two
  packs.
- **Shared wins for bilingual people.** English plus German is one 498 MB pack. Per-language copies of the same model
  would be 996 MB.
- **What it costs:** someone who uses only German still gets weights that also know 24 other languages. That's not
  size anyone can remove: it's the same file.
- A smaller shared pack (2-bit, #203) would shrink every Parakeet language at once.

## 7. Seal's pack list (first cut)

| Pack | Kind | Languages | Size (on disk) | Policy | Who gets it |
|---|---|---|---|---|---|
| Speaker labels | diarizer | all | 240.6 MB | `prefetch` (first install and update) | everyone, right after install |
| Parakeet | speech | the 25 it covers; used for en, es, fr, de today (§6) | 498.0 MB | `onDemand`, requested at first run | caption language is one Parakeet wins |
| Hebrew captions | speech | he-IL | est. 200–500 MB | `onDemand`, requested at first run | Hebrew captions, only if it beats Apple (#201) |
| Serbian captions | speech | sr | unknown | `onDemand`, requested at first run | Serbian captions (#204), later |
| Serbian translation | translation | sr↔en | unknown | onDemand, owned only | later |

The pack count is far under Apple's 200, and the sizes far under 200 GB.

## 8. Measuring the app-size north star

Report these for every release, in `docs/perf/install-size.md`, newest first:

1. **Base install, per device:** App Store Connect's download and install size for the smallest and largest iPhone
   variant, iPad, and Mac ([App File Sizes](https://developer.apple.com/help/app-store-connect/manage-builds/view-builds-and-metadata)).
   Before upload, use the `App Thinning Size Report.txt` from an export with "All compatible device variants"
   ([Reducing your app's size](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)).
2. **Each pack:** download size (`AssetPack.downloadSize`) and on-disk size (manifest `sizeOnDisk`).
3. **Per person:** the table in §3, recomputed: base + the packs each person gets.
4. **One script** (follow-up ticket): build Release, sum the bundle and each pack, zip-estimate, write the table. It
   does what this design did by hand.

Why it matters, in Google's words: size "can negatively impact install success and increase uninstalls"
([Reduce your app size](https://developer.android.com/topic/performance/reduce-apk-size)). Over 200 MB, the App Store
flags the build against "the 200 MB over-the-air download limit" (App Store Connect, link above). Google once
measured 1% fewer installs per 6 MB under 100 MB, but that's an old, secondary source.

## 9. What changes in the code (after approval; ordered tickets)

1. **ModelPacks seam** in CaptionCore: resolve a pack to a folder URL (bundle first, then asset pack), verify it
   against `pack.json` once per version, and report state (missing / downloading(p) / ready / failed). Pure, with
   fake sources in tests. Engine factories take URLs from it, as ADR 0014/0025 already require.
2. **Apple-hosted packs**: the StoreDownloaderExtension target, App Group and Info.plist keys, `ba-package` packaging
   in `scripts/`, and the two existing models as packs. Release builds stop bundling them. Debug builds keep them.
3. **Downloads page** in Settings (§4), with screenshots per the PR rules.
4. **Translation: Your languages** (§5, ADR 0031), extending `TranslationCenter`'s single `target` to a list with
   a minimum of one.
5. **UI language rule** (§2, ADR 0030): `preferredLocales`, the UI language first in `CaptionLanguage.resolve`,
   and the system Language row.
6. **iPhone probe** of Apple's language lists on iOS 26 and 27 (§6).
7. **Hebrew via DictationTranscriber**, behind the existing `SpeechRecognizerBackend` seam, after the Hebrew
   measurement (Hebrew research T1).
8. **Size report script** (§8).
9. **Right-to-left** (§2, ADR 0030 points 7–10), after the owner's `rtl-*` answers: the bracket buttons, the
   caption area's direction from the caption language (live, saved, translation lines, face-to-face halves), selection
   for right-to-left text, the shared transcript's direction marks, counted strings with plural variants. Each with
   pseudolanguage screenshots of every screen.
10. **Hebrew localization** of the UI, then Arabic: native-speaker wording and review (#38's rule), screenshots of
    every screen on a Hebrew phone. Only this makes a Hebrew phone show the mirrored app.
11. **Best engine per language** (§6): the language → engine table in CaptionCore (Parakeet for en, es, fr, de;
    Apple's elsewhere), `CaptionEngineFactory` and `EngineFallbackPolicy` reading it instead of "Parakeet is English
    only", and the first-run request for that engine's pack. Unit tests per group, and screenshots of the first-run
    progress line on a German phone.
12. **Measure the other 21 Parakeet languages** with #158's harness, one table row each; every win is a one-line
    change to the table in ticket 11.

## 10. Risks and unknowns

- **Core ML from an asset pack is untested.** FluidAudio's `loadLocal` and Core ML need a folder URL. `url(for:)`
  gives one, but whether a compiled `.mlmodelc` inside a pack loads (and compiles for the phone) from it is
  unverified. That's the first spike of ticket 2. If it fails, the fallback is copying the folder out once into
  Application Support. That copies 739 MB, so the copy would double the disk use while it runs.
- **Pack downloads may fail.** Forum reports say Apple-hosted pack downloads failed on iOS 26.4–26.6. Seen only in a
  search summary, not read. Seal's fallbacks (Apple's engine; captions without speaker labels) make that a quality
  drop, never "no captions".
- **Cellular:** Apple documents no cellular rule for asset packs. A 498 MB pack over mobile data could surprise
  someone. Proposed: show size before any on-demand download, and wait for Wi-Fi unless the user taps "Use mobile
  data" (Decision `cellular`).
- **The App Store's "In-App Content" setting** ("Automatically download in-app content in the background before
  the first time you open the app", [iPhone guide](https://support.apple.com/guide/iphone/change-settings-and-restrictions-iph3dfd91de/ios))
  probably gates `prefetch`. A user who turned it off gets the packs only when Seal asks on first launch.
- **Airplane-mode first launch** loses speaker labels until a network appears, which the bundled 1.1 doesn't.
- **Review:** packs need App Review, and a live pack update reaches every installed version at once.
- **iOS 27 deprecations:** `assetPack(withID:)`, `allAssetPacks` and `ensureLocalAvailability(of:)` are deprecated
  in 27.0 ([AssetPackManager](https://developer.apple.com/documentation/backgroundassets/assetpackmanager)). Seal
  builds with the 26.6 SDK today, so the seam wraps both forms.

- **Right-to-left checks without a native speaker.** The pseudolanguage catches layout, not wording. A mirrored
  screen with machine-made Hebrew could look done and read wrong; #38's review rule is the guard.
- **Bidi in mixed lines.** A Hebrew caption with an English name or a number in it is laid out by the Unicode bidi
  algorithm. Usually right, sometimes surprising (punctuation at the wrong end). To test with real Hebrew captions
  once the Hebrew engine runs (#201).

## 11. Space and time

- Disk: base + Σ(packs the user chose). No pack is ever copied (unless the Core ML fallback above is needed: 2× for
  the copy's duration).
- Verifying a pack is O(pack bytes), once per pack version (≈2–3 s for 498 MB at SSD hash speed, *estimate*),
  never per launch.
- Language lists: O(languages) per Settings open. Nothing runs in the captioning loop.
