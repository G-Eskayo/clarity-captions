# How From, Into and Face to face behave (spec)

**Scope:** owner's decision on PR #256 (2026-11-09): to write the intended behavior and build status of the three language-selection interfaces in one spec, drawn from code that already exists and from features decided but not yet built. This doc lists what is and what will be, never what is open or under debate.

**References:** issue #37 (caption language), #53 (translation), #245 (face to face, closed), #251 (Into list showing unsupported, open), #252 (two downloads of one locale, open), PR #256 (owner decision to write this spec), ADR 0031 (translation languages saved).

---

## From (caption language)

The language people speak, chosen before captioning starts.

| Behavior | Status | Notes |
|----------|--------|-------|
| **Install immediately** | Built (ADR 0030, 0031) | Speech model must be installed before first captioning session starts. Progress shown as "· 15%" etc. during install (`CaptionLanguageCenter`, `SpeechDownload`). |
| **Download with real %** | Built | Real-time progress shown while installing model (e.g., "· 15%"). |
| **Download fails / stalls** | Built | Failure message is shown in plain words: "Check that Wi-Fi is on and try again." Stall detected after 90 ticks of no progress (`SpeechDownload.swift`'s `StallWatch`, limit 90), shown via `CaptionLanguageDownloadLine`'s `.failed` case. |
| **Second pick while one downloads** | Built | A new pick doesn't cancel the old download. The old `SpeechDownload` runs until it finishes or stalls; its result is then discarded by `change.finished()`'s locale guard. If she picks the same locale twice before the first download finishes, two parallel downloads start (root cause of #252's double-download log): `SpeechDownload.language(_:)` makes a fresh instance with a fresh single-flight lock each call, not a cached one. |
| **Change From while captioning** | Decided, not built (owner, #279) | Not allowed. Tapping a language while the engine is running will show a message explaining why she must stop first, then tap again after stopping. Requires a follow-up ticket (check: `CaptionLanguageCenter.choose()` / `.set()` has no such check today). |

---

## Into (translation target)

The language captions are translated into, chosen before or after captioning starts.

| Behavior | Status | Notes |
|----------|--------|-------|
| **Install immediately** | Built | Translation pair downloaded with the language itself in Settings, before Into opens. |
| **Same language allowed and verified passthrough** | Built | If From = Into (e.g., English to English), captions are shown untranslated. `CaptionLanguage.needsNoTranslation()` is checked; `TranslationCenter.refreshConfiguration()` and `.passesThrough()` set each line's translation to its own text. No redundant translation work. |
| **Into's speech model download** | Built | When translating, Apple's TTS model is downloaded separately from the pair itself. Real % shown (e.g., "· 18%", `TranslationCenter.setUpIntoSpeech()`). Kept distinct from the translation-pair download (see below). |
| **Into's translation-pair download** | Built | Apple's Translation framework manages the pair download; shows its own progress sheet (no percentage on our screen). Today `TranslationTargetList.rows` filters to `supported` languages only. Owner's decision (tracked #251): every language will be shown, not-yet-downloaded pairs display "· downloading N%" like From, and unsupported pairs are greyed out with a reason — not yet built. |
| **Unsupported pair** | Built | When Apple's Translation doesn't have a pair (e.g., Cantonese), the engine is set to captions-only mode (no translation available). Today the list is pre-filtered to supported pairs only, so unsupported ones don't appear. Owner's decision (#251): all pairs will be shown, with unsupported ones greyed out and explained — not yet built. |
| **Change Into while captioning** | Decided, not built (owner, #279) | Allowed. New caption lines will use the new language; earlier lines stay translated as they were. Currently, `TranslationCenter.setTarget()` calls `translations.reset()`, which wipes `CaptionTranslations.done` — blanking every already-shown line's translation, not leaving them as they were. Requires a follow-up ticket. |

---

## Face to face

A split screen with two languages face-to-face: one shown in the other's language, live.

| Behavior | Status | Notes |
|----------|--------|-------|
| **Only ready pairs offered** | Built (closed #245) | Both speech models on device, translation pair downloaded. Checked at entry to the split. `FaceToFaceReadyLanguages` built and tested. |
| **Never starts a download itself** | Built (closed #245) | All setup is done upfront in Settings. The split only switches between ready languages and plays captions. |
| **Always-reachable Stop** | Built (closed #245) | Exits the split at any moment; any queued work is dropped. `SplitWorkQueue.cancelAll()` abandons queued operations without waiting. |
| **Per-half plain-words status** | Built (closed #245) | Each half shows what it's doing in plain words: "Listening", "Waiting for the other person to pick", "Paused", etc. (`FaceToFaceStatus.words(for:)`). Status matches the caption engine's state for her half and the app's state for his. |

---

## Known gaps (each needs its own ticket)

**Two downloads of one locale (issue #252, root cause confirmed above):** While she's downloading English, if she taps English again, a second download starts in parallel. Both finish independently; she sees one progress bar updating twice. The expected behavior: a second tap does nothing. The fix requires either making `SpeechDownload.language()` return a cached instance per locale, or moving its single-flight lock outside the instance. Not fixed in this spec.

**Same language tap-reveal redundancy (decision to open, below):** When From = Into (e.g., English captions, English translation), tapping a line shows "what was said" (unchanged text) identical to the translation above it. The expected behavior: either keep the reveal consistent (all folded lines tap open, even if nothing new shows) or skip it (no tap on same-language lines). This is the one genuine open question left; see the Decisions block.

---

## Decisions

<!-- marvin:decisions -->
### duplicate-reveal: Same language on both sides — when a line is tapped open, "what was said" repeats the translation above it word for word. Keep that, or skip the reveal when there's nothing new to show?

- [ ] A: Keep it — every folded line behaves the same way, tap always reveals "what was said" (consistent, even if it repeats)
- [ ] B: Skip it — a same-language line isn't tappable (or tapping does nothing), since there's nothing under the translation that isn't already on screen

<!-- /marvin:decisions -->
