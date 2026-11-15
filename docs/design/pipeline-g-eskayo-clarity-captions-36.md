## North-star fit

- **Reuses before adding anything new:**
  - `scripts/speech-locales/probe.swift`'s exact report shape (same five keys, same `ids(_:)` sort/format) — ported so an iPhone dump and the committed Mac JSON (`docs/research/apple-speech-locales-macos-26.5.1.json`) sit in one schema with no translation step.
  - `CaptionLanguage.bcp47` (`Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift:60`) for locale-id formatting, instead of re-deriving BCP-47 handling.
  - The existing debug-only developer panel (`Apps/Spike/Sources/ContentView.swift:1737` `developerPanel`, opened by the 1.5 s `DeveloperHold` long-press or by the existing `-ClarityDemoDeveloperPanel` flag in `DemoMode.swift`) instead of a new scene or launch flag — the pipeline's automatic screenshot step already reaches this panel.
  - `CaptionEngineRouting.parakeetLanguages` and `SealModel.forLanguage` (`Packages/CaptionCore/Sources/CaptionCore/EngineFallbackPolicy.swift:21-49`) — this **is** the "language → engine table" ADR 0029 describes as already living in CaptionCore; the new doc cites it rather than inventing a second table.
  - Already-measured sizes: Parakeet Ultra 6-bit shared pack, 498 MB (`docs/perf/install-size-2026-10-29.md`), Hebrew zipformer 4-bit pack, 38.6 MB (ADR 0025, PR #225/#220).
  - The existing evidence entry `docs/research/evidence/2026-10-30-apple-speech-locales-26-and-27.md` and its JSON — no new evidence-log entry, since nothing new is being researched, only written up (the owner's own 2026-11-11 instruction).
- **Simplest sufficient approach:** a small pure CaptionCore formatter (so it's unit-tested without a device) + one thin, explicitly-untested async call behind one new button in the panel that already exists and already screenshots. No new scene, no new ADR, no new dependency, no network.
- **Tokens:** spends a little on one new CaptionCore type + tests; saves by not re-deriving the macOS research or re-building a probe mechanism that already exists twice (Mac script + `CaptionLanguageCenter`'s own use of the same APIs).
- **Phone-OS direction:** N/A — this is an owner/developer diagnostic, never shown to a real user.
- **More capable, not more passive:** leaves the owner able to confirm the real iPhone data himself in one long-press + one paste, rather than MARVIN guessing at iPhone-only numbers Apple doesn't publish (confirmed unreadable in `docs/perf/install-size-2026-10-29.md`'s own "Not checked on iOS" line).
- **Correcting the ticket's stated scope:** the issue's "What to build" implies running a probe directly; the owner's 2026-11-11 comment narrows this run to (a) writing up what's already measured and (b) adding the one-tap on-device dump, with his own ~2-minute run left to him. This plan follows that narrowing, not the literal "What to build" text.
- **AC4 ("owner picks the launch set") is already answered in the thread**, not something to re-ask: Tier C = every locale the real iPhone reports (his "go for as many languages as we can"); Tier A begins with Spanish (his "lets start with spanish"). The concrete locale *list* is blocked on data (the on-device dump), not an open choice — so no Decisions section is needed for this ticket. Inventing one would violate decisions-format.md's "don't ask what's already answered."

## Tests first (CaptionCore, pure — the issue has no "How we'll try to break it" section, so these are the misuse cases the scope itself exposes)

New file `Packages/CaptionCore/Tests/CaptionCoreTests/SpeechLocaleReportTests.swift`, against a new pure `SpeechLocaleReport` type:

1. Empty supported/installed lists on all five fields → valid JSON, each array `[]`.
2. Duplicate locales that are the same BCP-47 id spelled two ways (`"en-US"` vs `"en_US"`) → deduplicated to one entry.
3. Same locales fed in two different input orders → byte-identical `asJSON()` output both times (determinism, needed to diff a Mac run against an iPhone run).
4. A region-less locale (`"he"`) → keeps its language-only id, no crash.
5. An "installed" locale absent from "supported" (a real-world API inconsistency) → recorded as-is in both lists, never silently merged or filtered out (ADR 0012's "dim, don't dismiss" spirit: show what the device actually reports).
6. The real special-cased ids already seen on this Mac (`hi-IN-translit`, `hi-Latn`, `es-419`) → each appears verbatim and distinctly, never collapsed together.
7. A stress list of 500 synthetic locales → completes and parses (guards a future OS reporting far more than today's ~63).
8. Round-tripping `asJSON()` through `JSONSerialization` yields exactly the five keys `probe.swift` already writes (`os`, `date`, `SpeechTranscriber.supportedLocales`, `.installedLocales`, `DictationTranscriber.supportedLocales`, `.installedLocales`, `SFSpeechRecognizer.supportedLocales`) — schema compatibility with the committed Mac JSON.

`Apps/Spike/Sources/SpeechLocaleDump.swift` (the real on-device async read of `SpeechTranscriber`/`DictationTranscriber`/`SFSpeechRecognizer`) is **explicitly untested**: it needs live Speech-framework data that differs by device and isn't available to XCTest or the simulator in a meaningful way. Stated plainly in the PR, per the playbook.

## Decisions

None needed. AC4's policy is already settled by the owner's own comments (Tier C = every iPhone-confirmed locale; Tier A starts with Spanish); the only thing missing is data (the real iPhone list), not a choice, so there is nothing to put in a `<!-- marvin:decisions -->` block.

## Task List

1. Add `SpeechLocaleReport` (pure type) to `Packages/CaptionCore/Sources/CaptionCore/SpeechLocaleReport.swift`: takes the four `[Locale]` lists + an OS string, formats via `CaptionLanguage.bcp47`, dedups, sorts, and exposes `asJSON()` matching `probe.swift`'s schema.
2. Write `SpeechLocaleReportTests.swift` with the 8 cases above; run `swift test --package-path Packages/CaptionCore` to confirm green.
3. Add `Apps/Spike/Sources/SpeechLocaleDump.swift`: a thin `static func current() async -> SpeechLocaleReport` that awaits `SpeechTranscriber.supportedLocales`/`.installedLocales`, `DictationTranscriber.supportedLocales`/`.installedLocales`, `SFSpeechRecognizer.supportedLocales()`, and `UIDevice.current.systemName`/`systemVersion`, mirroring `CaptionLanguageCenter.refresh()`'s existing use of the same APIs.
4. In `ContentView.swift`'s `developerPanel` (`:1737`), add one `#if DEBUG` button "Copy speech locales" that runs `SpeechLocaleDump.current()`, copies `asJSON()` to `UIPasteboard.general`, and sets a short on-screen confirmation (e.g. "Copied N locales, iOS X.Y.Z").
5. (Small, optional, same existing idiom as `-ClarityDemoSaidOpen`) add a `-ClarityDemoLocaleDumpCopied` doc-commented flag in `DemoMode.swift` that pre-sets the confirmation text, so the pipeline's automatic screenshot can show the post-tap state as well as the panel itself, since `simctl` can't tap.
6. Write `docs/research/caption-language-list.md`: cites the macOS 26.5.1 probe JSON and the existing evidence entry for the macOS 26/27 counts and gaps; records known sizes (Parakeet 498 MB shared across its languages, Hebrew 38.6 MB pack) and states plainly that Apple exposes no per-locale asset size via any API; marks the real iPhone list and its differences from macOS as **pending** the owner's one on-device run of the new "Copy speech locales" button, with the exact paste target (`docs/research/apple-speech-locales-ios-<version>.json`, same schema as the Mac file) spelled out; records the already-settled Tier A/B/C launch-set policy and that Spanish starts Tier A.
7. Verify `swift test --package-path Packages/CaptionCore` and the app-build step (`xcodebuild`) both pass; confirm the new button appears in the pipeline's automatic developer-panel screenshot (existing `-ClarityDemoDeveloperPanel` flag — no new scene).
8. PR: name the ticket in commits (`Refs #36`), link the new doc and screenshot, and state plainly that the real iPhone locale list and sizes remain unmeasured until the owner's on-device run — this PR does not claim AC1 is fully closed, only that the tool and write-up are ready for his ~2-minute confirmation.