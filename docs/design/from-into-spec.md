# From and Into: translation language pair behaviour (#279)

Owner decisions approved 2026-11-10, no app code changes until approval. Builds on #37 (caption language), #53/#171 (translation purchase), #245 (Into's speech model), #252 (From shows progress), #256 (no swap button), and #208 (face to face).

---

## Summary

**From** is the caption language, shown with its download progress when one is running.

**Into** is the language captions are translated into. The list shows every language the device can translate into — ones not yet downloaded show their download progress, ones this device can't translate into are greyed out with the reason.

**Changing From while captioning is not allowed** — the From control says "Stop captions to change" and becomes non-interactive.

**Changing Into while captioning is allowed** — new caption lines use the new Into language, and lines already on screen keep the Into language they had.

**Face to face** (#208) uses the same From/Into rules in each half; each half sets its own languages independently.

---

## The From row

The From row shows the caption language, with its download progress when one is running.

| Case | What From shows | What happens |
|---|---|---|
| **Caption language ready, no download** | `French (France)` | The current caption language. Tapping opens the language list; a new pick starts downloading if it needs one, and the From row updates. |
| **Caption language downloading** | `French (France) · downloading 40%` | A download is in progress. Shows real progress while it runs, from `CaptionLanguageSwitch`'s phase (PR #256, fix/252-swap-languages branch). The row updates once per second while downloading, and stays updated once the download settles. |
| **Download stalled** | `French (France) · downloading 0%` | The download paused but the device has a network connection (e.g. a slow or throttled connection, or a server stall). Tapping the language row doesn't retry; that's a future feature. |
| **Download failed** | Shows the caption language that is actually running (likely the fallback) | `CaptionLanguageCenter.current` shows the language captions are really in. The "Caption language" section below From/Into says why the failed language couldn't download (e.g. "network error", from `CaptionLanguageSwitch.FailReason`). A new pick in the list starts a new download attempt. |
| **Changing From while captioning** | `French (France) · Stop captions to change` | **Not yet built.** Captions are running, so From can't change (owner's rule, #279). The From row shows the message and becomes non-tappable (styled using the `tourRow`/`canShowTour` pattern, `SettingsPage.swift:467-483`). The `LanguageSettingsState.from` property on the caption page (currently always returns a tappable row) would gate this when built. |

### From's interaction with From row

- **Single download at a time:** only one caption language downloads at once. A second From pick replaces the first download (not queued). **Abandoned downloads:** the first pick's download continues to completion in the background after being abandoned, but its progress is no longer shown on the From row. The download doesn't appear on screen after the pick is abandoned.
- **No automatic fallback during download:** while a download runs, if it fails, captions fall back to Apple's engine on that language if Apple has it, or to the prior language if not. From shows the download attempt's result (settled at 100%, or failed). The Caption language section shows what's really running.
- **From row never blocks From interaction:** the download is informational. The user can keep tapping the row and changing picks at any time, which replaces the current download. There is no "cancel download" button.

---

## The Into list

The Into list shows every language the app can translate captions into, sorted by readiness and name (owner's rule from #256). Each language shows why it isn't ready if it isn't: download running, waiting to download, or unsupported on this device.

| State | Label | What happens |
|---|---|---|
| **Ready** | `English` (plain text, no icon) | Apple has this translation language on the device. Tapping picks it and starts translating right away. |
| **Downloading** | `English · downloading 45%` | The translation capability is being downloaded on-demand. Once #251 (readiness model) ships and the Into list reflects real-time progress, this state will show real progress. Tapping does nothing (selection is locked). **Separate:** the Into speech model (#245) downloads for face-to-face and shows progress in Settings (line 258, `SettingsPage.swift`), not here on the Into pick list. |
| **Waiting to download** | `English · waiting` | **Not yet built.** The language is available but hasn't been downloaded; it will download when the user picks it (on-demand asset pack). Once #251 (readiness model) is merged, this appears as a phase. |
| **Not available on this device** | `Chinese (Simplified)` (greyed out) with a note below, e.g. `"Needs iOS 27"` | This device's OS or Apple's support for the language doesn't allow it. A Chinese phone on iOS 26 gets greyed-out entries for languages that are iOS 27+ only. The note is determined by checking the device's speech support; the check and the mapping to reasons live in `CaptionLanguageCenter` (to be built after #37 updates). |
| **Not supported in this pair** | e.g. `Cantonese` (greyed out) with `"Cantonese can't translate English to Cantonese yet"` | Apple's translation doesn't support this pair, checked via `TranslationSession.isAvailable(from:to:)` (CONTEXT.md *On-device only* note, ADR 0031 point 5). Greyed out and explained plainly. |

### Into list interaction and rules

- **Changing Into while captioning is allowed.** New caption lines use the new Into language and its translation. **Lines that appeared on screen before the change keep the Into language they had.** **Not yet built:** Currently `CaptionTranslations` uses the live `target` value for all new work; the test coverage for this behavior is present in intent (`CaptionTranslationsTests` tests the core) but the actual feature — keeping earlier line translations when Into changes — is not implemented. `TranslationCenter.setTarget()` calls `translations.reset()` unconditionally (line 178), which clears all existing translations instead of preserving them.
- **Visible, not hidden:** The owner's rule from #256 (ticket #279 update): the Into list shows every language — ready pairs at normal text weight, unavailable ones greyed out with reasons. No language is hidden. This list is already built: `TranslationTargetList.rows()` returns all supported languages (with or without the same-language filter, per its branch state).
- **Into's speech model:** Each time Into changes, `TranslationCenter.setUpIntoSpeech()` checks whether the Into language's speech model is on the device (for face-to-face's split, where Into is a speech input). If it isn't, it downloads it in the background with progress shown in Settings under the Into row (line 258, `SettingsPage.swift`). The app never blocks on that download; if the split opens before it's ready, Into's half captures in Apple's engine, the same fallback as during caption language downloads.

---

## Same language on both sides

**Current state on fix/252-swap-languages (PR #256):** From and Into can be the same language. The filter at TranslationTargetList.rows() line 242 was removed (seen-insert only, no sameLanguage check). `TranslationCenter.setTarget()` accepts it and translates without filtering (passing the same source and target to `TranslationSession.refresh`). Tests pass in `CaptionTranslationsTests` on that branch.

**The two cases (same language allowed):**

| Case | What happens |
|---|---|
| **User picks the caption language as Into** | The Into list shows it (filter removed). Tapping it picks it and translation starts. |
| **Translating with From = Into** | `TranslationCenter.setTarget()` calls `TranslationSession.refresh` with the same source and target language. Apple's Translation API accepts the same language on both sides — the session doesn't reject it. Each caption line is passed through `TranslationSession` untranslated (it returns the input unchanged). **Already built** and tested (`CaptionTranslationsTests` on fix/252-swap-languages). |

---

## Face to face (#208)

Each half of the split (her words, and the other person's captions) picks its own From and Into languages. The From/Into rules above apply independently in each half:

| Part of split | From | Into | Interaction |
|---|---|---|---|
| **Her words** (the half the device is capturing) | the language she speaks in (a caption language the device supports) | the language the other person hears (one of their translation languages) | Each is picked from a list. If Into changes while captions are running in her half, new lines use the new language; earlier lines keep theirs. |
| **Other person's captions** (the half the other person speaks into) | the language the other person's words are in (a caption language the device supports) | the language her words are translated into (one of her translation languages) | Same as above, picked independently. |

For the language assignment, see #208 and `TranslationCenter.faceToFaceChanged()` at line 227 (the `LanguagePair` handling).

---

## Known open gaps

### "Abandoned pick's download keeps running in the background"

A From pick that starts downloading, then is abandoned (the user picks a different language before it finishes), leaves a download running on the phone until it finishes or the app stops. The download doesn't appear on screen after the pick is abandoned. The phone's system status bar shows the network activity if the user looks, but there's no feedback the download is still happening. The state is held in `CaptionLanguageCenter.change` and the Task that runs `SpeechDownload.language()` is never cancelled.

**Severity:** low. The download is using bandwidth the user picked once (to change caption languages), and stopping it would require more complex state management (a cancellation token, tracking abandonment). **Evidence:** this is the status quo from #37 (caption language downloads), and the owner has seen it — no complaint was filed. The language finishes downloading eventually, freeing the bandwidth, and Apple's speech engine captions meanwhile.

---

<!-- marvin:decisions -->

## Open Decisions

### from-download-recover: When a replacement From download fails, what happens to the one it replaced?

From the table: pick language A (downloading), then pick language B before A finishes (B replaces A, per "newest pick wins," already built). B's download then fails.

- [ ] A: Nothing — captions stay in the language that was current before A was ever picked; B's failure shows in the Caption language section; tapping From again retries
- [ ] B: Same as A, but From additionally offers one tap to go back to re-trying A instead of starting over
> **Note:** doesn't block approving the rest of the table — every other From case is decided.

### face-to-face-readiness: Should face-to-face's language list follow #245 (built) or #251's proposed rule?

**#245 rule (built, current):** tapping an Into language that hasn't downloaded yet starts its download with progress shown.

**#251 rule (proposed):** not-ready languages only ever show greyed out with a reason; no feature starts a download.

- [ ] A: Keep #245 as built until #251 ships, then switch
- [ ] B: Write the table to #251's rule now, as a stated future change to #245
- [ ] C: Leave this row open in the spec and decide it when #251 ships
> **Note:** doesn't block approving the rest of the table either.

<!-- /marvin:decisions -->

---

## Decisions history

- **2026-11-10:** Owner approved in ticket #279: From can't change while captioning (shows "Stop captions to change"), Into can change (new lines use new language, earlier lines keep theirs), Into list shows every language (not just ready pairs).
- **2026-11-10:** Owner approved this spec as a ticket for approval before more From/Into code is built (PR #256, the `spec` answer).
- **2026-11-09:** Swap button removed; From shows its download (PR #256).
- **2026-09-20:** #252 added same language support and From download progress.

---

## Tests

**Built on fix/252-swap-languages (PR #256):**

- From's download progress display: covered by `CaptionLanguageSwitch`'s phase tests and the From row's use of `LanguageSettingsState.from` which wraps `captionDownload`.
- Same language on both sides (fix/252-swap-languages only): tested in `CaptionLanguageListTests` and Apple's Translation handles it (both directions tested via the demo translator).

**Not yet verified (simulator-only):**

- From shows its download progress on a device (screenshots were taken in the simulator; #256 testing notes: "Not verified on a device: a real download of a new caption language with From on screen").
- Real same-language captioning with Apple's Translation on a device (simulator has no Translation languages; #256 testing notes).

**Not yet built:**

- From can't change while captioning (UI only: the From row and language list show "Stop captions to change" when captions are running; `LanguageSettingsState.from` would gate the row's tappability).
- Earlier lines keep their Into language when Into changes (would require not calling `translations.reset()` unconditionally in `TranslationCenter.setTarget()`).
