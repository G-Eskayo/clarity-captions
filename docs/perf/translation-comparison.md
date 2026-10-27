# Translation comparison: results and recommendation for 1.3 (#159)

Results of #159 "[E] Translation comparison test: Apple vs ML Kit vs open models, before 1.3", run 2026-10-26 on the
M4 Mac mini. Method: [`translation-comparison-design.md`](translation-comparison-design.md). Every table, with
confidence intervals and the speech and caption-style sets: [`translation-comparison-results.md`](translation-comparison-results.md).
Evidence log: E20 (licences, terms, delivery), E21 (results), E22 (every language Apple supports).

## Summary

- **Apple's Translation framework translates best in Spanish, French and German, on every set.** It beat the next
  best engine in each cell, and every paired 95% interval excludes zero. Against OPUS-MT base, the open model we
  could ship ourselves, it led by +1.8 to +4.5 chrF on written text and +3.6 to +7.9 on caption-style text.
  COMET agrees.
- **Apple loses the least when punctuation is missing.** Every engine scores lower on caption-style text, but Apple
  drops 2 to 7 chrF where the others drop up to 15. On German caption-style speech passages, Apple scores 60.5,
  OPUS-MT 52.6 and ML Kit 42.3.
- **OPUS-MT still beats Google's ML Kit on written text** in all three languages, by +1.8 to +4.6 chrF.
- **Everything is fast enough for captions.** Apple took 59 ms per caption line (p95 89 ms) on the M4. OPUS-MT base
  with greedy decoding took 35 ms (p95 107 ms), and ML Kit took 23 ms (p95 59 ms) in an Android emulator. These are
  Mac numbers, not iPhone numbers.
- **Only Apple puts up a system pop-up.** Its languages come through a system download sheet or Settings, and the
  app can't download them itself. In return the app ships no model and no runtime: about 286 MB per language pair
  lives in the system, shared with Apple's Translate app. ML Kit and OPUS-MT download under the app's control. ML
  Kit also sends usage metrics to Google and requires Google attribution.

## Results, written text

chrF (0–100, higher is better) on FLORES-200 devtest (1,012 sentences) and WMT24++ speech transcripts (111
passages). COMET (wmt22-comet-da) in brackets. 95% intervals are in the full tables.

| Pair | Set | Apple | OPUS-MT base | OPUS-MT tc-big | ML Kit | Apple − OPUS-MT base (95% CI) |
|---|---|---|---|---|---|---|
| en-es | FLORES | **56.8** (0.863) | 55.0 (0.849) | 56.5 (0.858) | 53.2 (0.805) | +1.8 (+1.4 to +2.1) |
| en-es | speech | **71.6** (0.806) | 68.9 (0.788) | 69.8 (0.792) | 65.2 (0.723) | +2.7 (+2.0 to +3.4) |
| en-fr | FLORES | **73.2** (0.879) | 69.8 (0.861) | 72.4 (0.877) | 65.4 (0.802) | +3.3 (+2.9 to +3.8) |
| en-fr | speech | **65.3** (0.778) | 62.2 (0.753) | 63.3 (0.764) | 59.5 (0.672) | +3.1 (+2.4 to +3.8) |
| en-de | FLORES | **68.2** (0.883) | 63.6 (0.847) | – | 59.0 (0.759) | +4.5 (+4.0 to +5.1) |
| en-de | speech | **64.3** (0.795) | 61.3 (0.764) | – | 57.4 (0.656) | +3.0 (+2.3 to +3.6) |

There is no tc-big model for en-de. Apple also beat tc-big, by smaller margins: +0.3 (en-es FLORES, CI +0.0 to
+0.6) to +2.0 chrF.

## Results, caption-style text

The same sources and references, lowercased with sentence punctuation removed, which is what a caption engine
without punctuation would hand over.

| Pair | Set | Apple | OPUS-MT base | OPUS-MT tc-big | ML Kit | Apple − OPUS-MT base (95% CI) |
|---|---|---|---|---|---|---|
| en-es | FLORES | **54.8** (0.840) | 51.2 (0.784) | 53.1 (0.813) | 51.8 (0.782) | +3.6 (+3.2 to +3.9) |
| en-es | speech | **65.8** (0.744) | 59.9 (0.638) | 56.5 (0.652) | 58.3 (0.605) | +5.9 (+5.0 to +6.7) |
| en-fr | FLORES | **69.7** (0.850) | 63.0 (0.784) | 66.5 (0.818) | 62.6 (0.765) | +6.7 (+6.2 to +7.3) |
| en-fr | speech | **58.7** (0.678) | 54.4 (0.596) | 51.6 (0.603) | 53.8 (0.549) | +4.3 (+2.9 to +5.4) |
| en-de | FLORES | **65.9** (0.861) | 58.2 (0.751) | – | 56.7 (0.721) | +7.7 (+7.1 to +8.4) |
| en-de | speech | **60.5** (0.734) | 52.6 (0.553) | – | 42.3 (0.475) | +7.9 (+6.8 to +9.1) |

On the speech passages (median 68 words) there is no punctuation to split on, so these cells also test long
unpunctuated input, which a caption app wouldn't send. OPUS-MT tc-big suffers most there.

## Speed, size and delivery

| Engine (en-es) | Median ms per line | p95 ms | Size per pair | Model reaches the phone by | System pop-up |
|---|---|---|---|---|---|
| Apple Translation | 59 | 89 | 286 MB on disk, 221 MB zipped, held by the system | system sheet or Settings | **yes** |
| OPUS-MT base, greedy | 35 | 107 | 82 MB on disk, 69 MB zipped | app download or bundle, our host | none |
| OPUS-MT base, beam 4 | 65 | 198 | same | same | none |
| OPUS-MT tc-big, beam 4 | 102 | 317 | 239 MB, 215 MB zipped | same | none |
| ML Kit | 23 | 59 | 46 MB (both directions) | app-controlled download from Google | none |

Speed: 760 EdAcc caption lines, one at a time, two repeats, model load and warm-up excluded. Apple and OPUS-MT ran
on the M4 with the machine quiet (load average about 5); Apple ran through `TranslationSession` on macOS 26.5.1,
OPUS-MT on the CPU (CTranslate2 int8, 4 threads). ML Kit ran in an arm64 Android 15 emulator on the same M4 while
another test was loading the machine (load average 16–28). Under that load OPUS-MT beam 4 measured 111 ms, so ML
Kit's quiet number is probably lower still. Every engine gave identical text on both repeats. Left untranslated
(output equal to input), out of 760: Apple 2, OPUS-MT 5, ML Kit 7, mostly "oh wow" or "okay okay". One of ML Kit's
was a whole 25-word sentence.

Apple's size is what the system installed for en→es: a shared encoder for its English, Spanish, German, Italian,
French, Portuguese and Dutch family, plus an English and a Spanish asset. Each further language in that family adds
about 80 MB. The system holds it, so none of it counts against Seal Speak's download, and a person who already uses
Apple's Translate app may have it. The zipped size is our estimate of the download; Apple doesn't show the real one.
ML Kit downloaded en-es in 6 s on the M4's connection. Its folder holds both directions and dictionaries.

## All languages Apple supports

**These are written-text numbers (FLORES-200 devtest, Wikipedia-style prose), not conversation.** They show how well
Apple translates each language on clean written English, not how it handles live speech or caption-style text.

On 2026-10-26 Gil installed every Translation language on the M4. `translation-eval --list` asks
`LanguageAvailability` for the status of English to each supported language, and 19 came back *installed*. FLORES-200
covers all 19. Spanish, French and German come from the main comparison above. The other 16 ran the same way:
Apple's framework on the 1,012 FLORES devtest sentences, then the 760 EdAcc caption lines twice for time per line,
one language at a time on a quiet machine, with 0 errors. COMET (wmt22-comet-da) was also run, because it took only
about 13 minutes for all 16. Only Apple was run here; no other engine was tested in these languages.

| Language | Apple code | chrF | 95% CI | COMET | Median ms/line | p95 ms | Assets on disk |
|---|---|---|---|---|---|---|---|
| Indonesian | `id` | 73.8 | 73.0 to 74.6 | 0.920 | 53 | 76 | 208 MB |
| Portuguese (Brazil) | `pt` | 73.6 | 72.7 to 74.5 | 0.899 | 51 | 78 | 285 MB |
| French | `fr` | 73.2 | 72.2 to 74.1 | 0.879 | 58 | 97 | 288 MB |
| German | `de` | 68.2 | 67.3 to 69.0 | 0.883 | 70 | 110 | 291 MB |
| Turkish | `tr` | 65.7 | 64.8 to 66.6 | 0.903 | 52 | 74 | 156 MB |
| Arabic | `ar-AE` | 63.1 | 62.1 to 64.1 | 0.870 | 53 | 76 | 155 MB |
| Vietnamese | `vi` | 62.5 | 61.6 to 63.3 | 0.892 | 52 | 77 | 209 MB |
| Ukrainian | `uk` | 61.8 | 60.9 to 62.7 | 0.898 | 51 | 79 | 210 MB |
| Hindi | `hi` | 60.9 | 59.9 to 62.0 | 0.807 | 52 | 76 | 154 MB |
| Italian | `it` | 60.4 | 59.8 to 61.1 | 0.879 | 52 | 77 | 284 MB |
| Russian | `ru` | 60.0 | 59.0 to 61.0 | 0.886 | 52 | 81 | 213 MB |
| Dutch | `nl` | 59.6 | 58.9 to 60.3 | 0.879 | 51 | 75 | 284 MB |
| Thai | `th` | 57.9 | 56.9 to 58.7 | 0.879 | 51 | 69 | 206 MB |
| Spanish | `es` | 56.8 | 56.2 to 57.4 | 0.863 | 59 | 89 | 286 MB |
| Polish | `pl` | 53.8 | 53.1 to 54.5 | 0.889 | 52 | 77 | 213 MB |
| Japanese | `ja` | 43.5 | 42.5 to 44.5 | 0.912 | 59 | 88 | 248 MB |
| Chinese (Simplified) | `zh` | 40.3 | 39.2 to 41.5 | 0.871 | 56 | 79 | 274 MB |
| Korean | `ko` | 38.0 | 37.1 to 39.0 | 0.899 | 56 | 79 | 247 MB |
| Chinese (Traditional) | `zh-TW` | 32.6 | 31.7 to 33.6 | 0.875 | 55 | 80 | 274 MB |

Generated by `python -m translation_eval.cli languages-report` into
[`translation-languages-results.md`](translation-languages-results.md) (JSON twin beside it). Assets on disk means the
language family's shared asset plus that family's English and target assets, read from
`/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Translation_Assets`. Languages in one family share the shared
asset and the English asset, so a second language from the same family adds only its own asset, about 40 to 90 MB.
Spanish's time per line is from the isolated timing pass. French and German times are from the main runs, which
overlapped with other work, so they read a little high.

**In plain words:**

- **Most languages look ready.** COMET is 0.86 to 0.92 everywhere except Hindi, the same range as Spanish, French
  and German, where Apple beat every other engine. Indonesian, Japanese, Turkish, Portuguese and Korean score highest
  on COMET.
- **Hindi looks weakest.** It has the lowest COMET (0.807), clearly below every other language, even though its chrF
  is mid-table. Check it before promising it.
- **Low chrF in Japanese, Chinese and Korean doesn't mean bad translation.** chrF counts character n-grams, and these
  scripts have no spaces and many characters per word, so their chrF runs low for any engine. COMET rates Japanese
  0.912 and Korean 0.899, among the best. Compare chrF within a language, not across languages.
- **Simplified Chinese sometimes comes back in Traditional characters.** Asked for `zh` (Simplified), Apple returned
  mostly Traditional characters in 29 of 1,012 FLORES sentences (2.9%) and 15 of 760 caption lines (2.0%). The
  reverse never happened: `zh-TW` output was all Traditional. A person reading Simplified would notice. Worth a check
  on an iPhone, and possibly a script conversion in the app.
- **Speed doesn't depend on the language.** The median was 51 to 59 ms per caption line in all 16 new languages.
- Spanish's chrF is lower than French's because the FLORES Spanish references are Latin American, not because Apple's
  Spanish is worse (COMET 0.863).

Caveats beyond those above: FLORES is written text; the caption-style and speech sets were not run in these
languages. Apple's Arabic is `ar-AE`, scored against FLORES's Modern Standard Arabic (`arb_Arab`). The 16 new
languages ran through a debug build of the `translation-eval` runner (the earlier three used a release build). The
time is spent inside Apple's framework, so the build shouldn't move it noticeably, but that wasn't measured.

## Things we learned on the way

- **Marian models drop sentences from long input.** Fed whole 68-word passages, OPUS-MT left 13 (base) and 21
  (tc-big) of 111 Spanish outputs under 70% of the reference length, against 0 for ML Kit, which splits on its own.
  Translating sentence by sentence fixes it (`translation_eval.split`); an OPUS-MT integration must do the same.
  Apple splits on its own too.
- **Greedy decoding costs nothing here.** FLORES 54.8 against 55.0 for beam 4 (COMET 0.847 against 0.849), at about
  half the time.
- **ML Kit can't run in the iOS Simulator on Apple silicon.** MLKitTranslate 8.0.0 has no arm64 Simulator slice, and
  the iOS 26.5 Simulator refuses x86_64 apps. An iOS ML Kit build would need a real device for every test.
- **ML Kit keeps a telemetry queue.** Its `datatransport` event database reached 10 MB over this test's runs.
- **Apple's framework needs a person in the loop even for testing.** The installed-languages session never shows the
  sheet, so a Mac test run needs the languages installed by hand in Settings first.
- One sample line suggests ML Kit softens profanity ("I wouldn't learn shit" became "I wouldn't learn"), while OPUS-MT
  kept it. That's one example, not a measurement, but captions for a hard-of-hearing person should say what was said.
  Worth checking for whichever engine ships.

## Caveats

- Mac CPU and Android emulator, not iPhone. Absolute times will differ on a phone; the quality ranking shouldn't,
  assuming iOS uses the same Apple language assets as macOS (likely, not verified).
- FLORES is written Wikipedia-style prose. WMT24++ speech passages are real transcripts, but paragraph-length.
- The Spanish references are Latin American (FLORES) and Mexican (WMT24++). The caption-style copies are synthetic.
  Real caption lines (EdAcc) have no reference translation, so they measure speed and failures only.
- Any engine may have seen FLORES or WMT data in training. That can't be checked for Apple or Google.
- Firefox's Bergamot wasn't run because there's no arm64 macOS build. It's MPL 2.0 and ships in Firefox on Android,
  so it stays a candidate for Android.

## Recommendation for 1.3

**Use Apple's Translation framework for 1.3, translating Parakeet's punctuated text.** It's the most accurate engine
in all three languages on every set, it needs no model or runtime in the app, and it's fast enough. This changes the
earlier recommendation (OPUS-MT), which was written before Apple could be measured.

This is ADR 0026's path. A feature may ship first on Apple's framework, and a cross-platform engine is preferred only
once it matches or beats Apple. On this test, none does.

The cost is the system sheet. Seal Speak shows no system pop-ups (E15), and Apple's languages arrive only through
its download sheet or Settings, which the app can't restyle or replace. The 1.3 design has to decide when the sheet
may appear, as an exception to that rule. That is Gil's call; this test only prices it. Before the ADR, an iPhone
check should confirm the time per line and memory use, and that the sheet appears when expected (a forum report says
it sometimes doesn't on first use, E15).

**OPUS-MT base is the cross-platform engine** for an Android version and the fallback if the sheet is ruled out. It
is second on written text, needs no pop-up, and has no third party, at the cost of shipping a runtime and about 65 MB
zipped per language. **ML Kit is third:** it loses to both on quality and adds Google telemetry and attribution.
