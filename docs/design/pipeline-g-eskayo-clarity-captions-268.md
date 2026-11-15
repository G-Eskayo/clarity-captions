## North-star fit

**Reuses before adding anything new:**
- `PercentileHistogram` (`Packages/CaptionCore/Sources/CaptionCore/BetaFeedback.swift`) for median/P95 of the three new delays — extended with one explicit running-max `Double` per metric, since histogram binning only approximates a max and this ticket asks for a real one.
- The `max(0, date.timeIntervalSince(...))` clamp idiom, used repeatedly in `ConversationRecorder` (`BetaFeedback.swift`, e.g. `captioningStopped`), for "no negative... delays."
- The transient-hash-without-text pattern already used twice: `ConversationRecorder.captionUpdate`'s `shownWordHashes`/`changedWords` (`BetaFeedback.swift`) and `EarPhrases.key`'s case/diacritic folding (`EarTranslation.swift`) — reused for repeat detection, so no caption text is ever retained, only a discarded hash.
- The bounded-dictionary-capping idiom already in `EarCenter.speak(_:translation:)` (`speakers.count > 200` → filter), reused to bound the new tracker's in-flight-phrase table for a 2-hour session.
- The optional-additive-field + `CodingKeys` pattern already used for `context: CaptioningContext?`, `engine`, `engineFallback` (`BetaFeedback.swift`) — the new `ear` field decodes as `nil` for every conversation recorded before this build, no migration needed.
- The `guard isOn else { return }` gate already on every other `BetaFeedbackCenter` method (`audioLevel`, `captionUpdate`, `tick`) — the new ear-event methods follow the same fail-closed mechanism (ADR 0023); no new gate invented.
- `EarCenter`'s existing `AVSpeechSynthesizerDelegate` callbacks the ticket itself names: `willSpeakRangeOfSpeechString` (first call = voice start) and `didFinish`/`didCancel` → `finished(_:)` (voice end/cut-off).
- The `-ClarityDemoEar <variant>` launch-argument family (`DemoMode.swift`) for the new screenshot scene, instead of a new demo-arg scheme.

**Why simplest sufficient:** one small pure-Swift struct (`EarDelayRecorder`), same shape as `WordLagTracker`/`PercentileHistogram`, fed by events that already fire at 4 existing call sites (`EarPhrases.take`, `EarCenter.speak`, `willSpeakRangeOfSpeechString`, `finished`). No new persistence (rides inside the existing `ConversationRecorder` → `FeedbackStore` → Messages pipeline), no new network, no new dependency. Delay math only needs the four timestamps to share one consistent clock — it doesn't need to be literally `FedAudioClock`, just internally consistent — so `Date()` is used throughout, matching every other `ConversationRecorder` event instead of inventing a second clock concept.

**Tokens/cost:** one-time build cost (new type + tests + schema doc + app wiring); no ongoing cost — each event is O(1) time, and `open`/`recentFinals` are capped at small constants, so memory is O(1) regardless of session length (north star 1, "Space/time complexity = correctness").

**Phone-OS direction:** neutral — this is an instrumentation feature, not a reachability/generality change.

**More capable or more passive:** makes the owner more capable at tuning a real product (real numbers instead of "vibes," his own words, 2026-11-04) — the tester sees an optional, tiny, TestFlight-only readout; nobody is made more passive.

## Existing behavior already covered, no new code needed

- Face-to-face / two speakers overlapping (`EarPhrases.isSpoken`, `TranslationCenter.earActive = isActive && !faceToFace`): the ear pipeline is already structurally off during face-to-face, so it never emits events there. Verified by a report-shape test, not new gating.
- "An App Store build records nothing": already covered by `BetaEnvironment.featuresOn` and the `guard isOn else { return }` gate every `BetaFeedbackCenter` method uses; the new methods add no new surface.

## Tests first (CaptionCore, `EarDelayTests.swift`)

Per the ticket's attack list, plus the misuse categories it didn't name:

1. **Rewritten/re-issued phrase, one line not two**: calling `translationReady`/`voiceStarted` twice for the same `(lineID, wordStart)` key only counts once in the histograms (idempotency guard on the pending entry).
2. **Translation never arrives**: `phraseEnded` with no following `translationReady`/`voiceStarted` adds nothing to any histogram and leaves no permanent trace.
3. **Voice cut off by the next line**: `voiceEnded` (didCancel) after `voiceStarted` doesn't crash, doesn't re-add to histograms, and a stray `voiceStarted`/`voiceEnded` replay for an already-closed key is a no-op.
4. **Headphones unplugged / Airplane Mode / backgrounded** (abandoned open phrase): an entry older than the age cap is evicted and never resolves into a delay.
5. **Wrong order**: `translationReady` or `voiceStarted` called before any `phraseEnded` for that key is a safe no-op (no negative, no crash).
6. **2-hour session, bounded memory**: thousands of complete phrase lifecycles leave `PercentileHistogram`'s fixed bin count unchanged (cites its own doc comment) and `open`/`recentFinals` never exceed their caps (verified behaviorally: an old key outside the window can no longer be resolved/matched).
7. **Clock change mid-session**: a later event's `Date` earlier than an earlier event's `Date` clamps the computed delay to 0, never negative, never throws.
8. **Two speakers overlapping on iPad face to face**: no ear events ever occur for such a conversation → `ConversationReport.ear` is `nil`, not zeros.
9. **Bad/empty/malformed input**: `lineFinished("")`/whitespace-only text is a no-op (mirrors `CaptionStream.apply`'s `guard !piece.isEmpty`); a very long line hashes in O(1) without issue; accented/differently-cased repeats of the same words still match (reuses `EarPhrases.key` folding), while genuinely different text never falsely matches.
10. **Growing backlog ("behind by")**: three phrases whose `phraseEnded` times advance while their `voiceStarted` times lag behind show a strictly increasing `behindBy` sample for the later ones (the "growing backlog" the ticket names).
11. **"The one a listener feels"**: `voiceStartDelay` for a normal (non-early) phrase equals `voiceStarted - phraseEnded` exactly, with median/P95/**max** all reported (max as an exact running value, not histogram-bin-approximated).
12. **Repeat count**: an identical finalized line within the recent window counts once as a repeat; the same line finalizing only once never self-counts; a line outside the window doesn't match.
13. **Backward compatibility / stale state**: a `ConversationRecorder` JSON blob missing the `ear` key (as every pre-#268 stored or in-flight conversation will be) decodes with `ear == nil`, and the report shows `"ear": null` for it.
14. **Report shape**: `entry(now:)` omits per-field percentiles (nils) when `ear` exists but has zero samples of a given metric, same convention as `Lag`.

## Decisions

<!-- marvin:decisions -->
### repeat-scope: Should the repeat count only cover lines spoken through the ear/voice pipeline, or every finalized caption line?
- [ ] Ear-pipeline lines only — scoped to this feature, costs nothing when "Speak it in my ear" is off, but says nothing about repeats when translation is off
- [ ] Every finalized caption line, regardless of whether ear/translation is on — a general "she had to repeat herself" signal, but mixes a non-ear concept into the `ear` schema block and runs even when the feature nobody's testing is off

## Owner-gated item (flagged, not decided here)

The live readout's look (AC4: "approved by the owner from mock-ups before it ships") is a look change. Per this repo's existing process, that approval happens through the PR's required screenshots (the pipeline's look-proof stage), the same way "folded translated caption" and other `#233` UI shipped — not a separate out-of-band mock-up step. I'll build the small `ear 1.8 s · behind 0.4 s`-style readout, gate it behind TestFlight (`BetaFeedbackCenter.shared.isOn`) and `EarCenter.state.speaks`, add a debug-only scene for it, and let the PR's screenshots stand as the mock-up for review — flagging here per the owner-gate instruction, not deciding it myself.

## Untested by `swift test` (stated plainly)

Everything in `Packages/CaptionCore` above is unit tested. The app-layer wiring is not, and can't be run by me:
- Threading the active `ConversationSession` into `TranslationCenter`'s one-way loop and into `EarCenter` so the four new `BetaFeedbackCenter` calls target the right recorder.
- The actual `AVSpeechSynthesizerDelegate` callback wiring in `EarCenter` (first `willSpeakRangeOfSpeechString` per utterance, `finished(_:)`).
- The live readout view and its visibility/text.

## Task List

1. **CaptionCore — `EarDelay.swift`**: add `EarDelayRecorder` (Codable/Equatable/Sendable): `phraseEnded`, `translationReady`, `voiceStarted`, `voiceEnded`, `lineFinished`, each with the clamping/eviction/idempotency behavior from the tests above; exact running max alongside each `PercentileHistogram`.
2. Write `EarDelayTests.swift` covering all 14 cases above, before wiring it into `ConversationRecorder`.
3. **CaptionCore — `BetaFeedback.swift`**: add `ear: EarDelayRecorder?` to `ConversationRecorder` (+ `CodingKeys`), mutating passthrough methods (`earPhraseEnded`, `earTranslationReady`, `earVoiceStarted`, `earVoiceEnded`, `earLineFinished`); add `ConversationReport.Ear` (nested `DelayStats { p50Seconds, p95Seconds, maxSeconds }` × 3 + `repeatCount`), wired into `entry(now:)` and its custom `encode(to:)`.
4. Extend `BetaFeedbackTests.swift` (or the new test file) with report-shape tests: `ear` nil when untouched, populated correctly when fed, decodes old JSON without it.
5. **`docs/beta/metrics-schema.md`**: add the `ear` block to the shape example and its field table row, additive, "still schema 1," following the exact phrasing precedent of the `engine`/`captionLanguage` rows.
6. **App wiring (`TranslationCenter.swift`, `EarCenter.swift`)**: thread the active `ConversationSession` through to the one-way `ear.take`/`ear.speak` call sites; call `BetaFeedbackCenter.shared.earPhraseEnded`/`earTranslationReady` there; add `earVoiceStarted`/`earVoiceEnded` calls inside `EarCenter`'s `willSpeakRangeOfSpeechString` (first call only) and `finished(_:)`; call `earLineFinished` where finalized line text is available (`EarPhrases.take`'s caller already sees `[CaptionLine]`). Explicitly skip the demo/simulator fill paths (`demoFill`) so screenshots never pollute real beta data.
7. **Live readout (owner-gated, see above)**: small text view under captions, visible only when `BetaFeedbackCenter.shared.isOn && EarCenter.shared.state.speaks`, showing the most recent voice-start delay and behind-by (ephemeral `@Published` values on `EarCenter`, computed separately from the persisted recorder — not worth sharing an abstraction for one subtraction, per Colton's test). Add a debug-only `-ClarityDemoEar` variant (or extend an existing one) to reach it for the pipeline's own screenshot stage.
8. Build stage: `swift test --package-path Packages/CaptionCore` green; state time/space complexity (O(1) per event, fixed-size histograms and capped tables) in the PR description.
9. App-build stage: `xcodebuild` green for the Simulator profile; note in the PR which behavior (item in "Untested by `swift test`" above) couldn't be verified directly.
10. PR: screenshots of the new readout scene for the owner's look approval, and the Decision above for his pick on repeat-count scope.