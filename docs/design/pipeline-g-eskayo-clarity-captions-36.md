No prior work in flight for #36. I have everything needed to produce the plan.

## North-star fit

**Reuses before adding anything new:**
- `scripts/speech-locales/probe.swift`'s exact JSON schema (`os`, `date`, `SpeechTranscriber.supportedLocales`/`installedLocales`, `DictationTranscriber.supportedLocales`/`installedLocales`, `SFSpeechRecognizer.supportedLocales()`, sorted + `JSONSerialization(.sortedKeys, .prettyPrinted)`) so the iPhone dump sits beside the already-committed `docs/research/apple-speech-locales-macos-26.5.1.json` in the same shape.
- The developer panel in `Apps/Spike/Sources/ContentView.swift` (`developerPanel`, the `DeveloperHold` long-press, the `latencyReport` / "Measure latency" button pattern at line ~1756) for the new "Speech locales" button — same debug-only disclosure, same `@Published ... Report: String?` shape, same `UIPasteboard.general.string` copy pattern already used for caption text (`ContentView.swift:1618`).
- `CaptionLanguage.bcp47` (`Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift`) for locale→string formatting.
- Already-committed research: `docs/research/evidence/2026-10-30-apple-speech-locales-26-and-27.md`, the macOS 26.5.1 JSON, `docs/research/languages-batch/apple-27.md`, and `EngineFallbackPolicy.parakeetLanguages`/ADR 0029 for sizes — none of this gets re-derived.
- The owner's own already-given answers in #36's comments (Tier A/B/C, 2026-10-05; "start with Spanish", 2026-10-05) for the "launch set" acceptance criterion, rather than re-asking.

**Simplest sufficient approach:** one small pure formatter in CaptionCore + a button reusing an existing debug panel + a write-up doc. No new screen, no new `DemoMode` flag, no new CaptionCore gating logic — building Tier A/B/C *enforcement* into the app is explicitly out of scope per the owner's 2026-11-11 comment, which only asks for the write-up and the one-tap tool.

**Tokens:** spends a little now (one ~30-line pure type, tests, a doc) so that finishing the real deliverable after the owner's one device run is a five-minute paste, not a new research pass.

**Leaves the user more capable:** the one physical thing only he can do (plug in the real iPhone, tap a button, paste the result) stays his; the tool hands him plain locale lists, not a decision made for him.

## Tests (write first)

The ticket gives no "How we'll try to break it" list, so these are the misuse cases for the one new piece of logic, `SpeechLocaleReport` (pure, in `Packages/CaptionCore/Tests/CaptionCoreTests/SpeechLocaleReportTests.swift`):

1. **Repeats** — each of the five input lists has a duplicate entry → each appears once in the output JSON.
2. **Empty input** — all five lists empty (the real A13-iPhone case, per `apple-27.md` §2) → valid JSON with `[]`, not `null` or a crash.
3. **Huge input** — a few hundred synthetic locale strings → valid, untruncated JSON.
4. **Malformed input** — a locale string containing a quote/backslash/unicode → still valid, parseable JSON (defensive: real `Locale` IDs won't produce this, but the formatter must not corrupt the committed file if it ever does).
5. **Schema pinning** — the JSON's key names exactly match `scripts/speech-locales/probe.swift`'s five keys plus `os`/`date`, so the iPhone and Mac files stay comparable (a person's mistake: silently renaming a field later).
6. **Plain language on zero** — `summary()` with empty lists states the counts plainly ("0 ...") rather than a confusing or crashing format string (ties to ADR 0012's plain-language rule).
7. **Counts match supplied lists** — `summary()`'s counts equal the deduped array counts, pinning the dedup-vs-raw choice under a test.

**Not applicable / explicitly untested:** concurrency, "each dependency failing", wrong permissions and stale state don't apply to a stateless pure formatter. What genuinely can't be tested here: the real `SpeechTranscriber`/`DictationTranscriber`/`SFSpeechRecognizer` values on a real iPhone, and the developer-panel tap→copy UI flow — the simulator has no real Speech support for most locales and this agent cannot tap a device. Said plainly in the PR.

## Decisions

None open. The owner already answered the framework (Tier A/B/C, 2026-10-05), the starting language (Spanish, 2026-10-05), and fixed this ticket's remaining scope to a write-up plus a one-tap tool (2026-11-11) — all in #36's own comments. Nothing here needs a fresh choice.

## Task List

1. [ ] Add `Packages/CaptionCore/Sources/CaptionCore/SpeechLocaleReport.swift`: pure `json(os:date:speechTranscriberSupported:speechTranscriberInstalled:dictationSupported:dictationInstalled:sfSpeechSupported:) -> String` (sorted, deduped, same key names/shape as `probe.swift`) and `summary(os:speechTranscriberSupported:dictationSupported:) -> String`.
2. [ ] Add `SpeechLocaleReportTests.swift` with the 7 tests above; `swift test --package-path Packages/CaptionCore` green.
3. [ ] Add a "Speech locales" button to `developerPanel` in `Apps/Spike/Sources/ContentView.swift`: reads the five Speech-framework lists (`await`), maps via `CaptionLanguage.bcp47`, calls `SpeechLocaleReport.json`, copies it to `UIPasteboard.general.string`, and shows `SpeechLocaleReport.summary(...)` in a new `@Published var localesReport: String?` next to `latencyReport`. Uses `UIDevice.current.systemName/systemVersion` for `os`, `ISO8601DateFormatter` for `date`.
4. [ ] Write `docs/research/launch-languages.md`: the macOS 26.5.1/27.0.1 lists (from the committed JSON + evidence file + `apple-27.md`), download sizes grouped by engine (0 MB per Apple-engine locale per ADR 0029; 498 MB shared Parakeet pack for en/es/fr/de/it/pt per `EngineFallbackPolicy.parakeetLanguages`; per-language Seal-pack estimates from `languages-batch.md` §4/§7), the Tier A/B/C framework and the decided launch set (every engine-covered locale at Tier C; Spanish first), and an explicit "iPhone not yet confirmed" section giving the owner's exact step (open the Xcode debug build → long-press the status word → "Speech locales" → paste into `docs/research/apple-speech-locales-iphone-<version>.json`).
5. [ ] One-line edit to `docs/research/languages-batch.md`'s "To close this" / §2 note, pointing at the new developer-panel tool instead of "needs a debug-build log".
6. [ ] Open the PR stating plainly which behavior is untested (step 2 above) and that acceptance criteria 1 and 3 close only once the owner's device run lands and its JSON is committed.