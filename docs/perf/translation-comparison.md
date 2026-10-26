# Translation comparison: results and recommendation for 1.3 (#159)

Results of #159 "[E] Translation comparison test: Apple vs ML Kit vs open models, before 1.3", run 2026-10-26 on the
M4 Mac mini. Method: [`translation-comparison-design.md`](translation-comparison-design.md). Every table, with
confidence intervals and the speech and caption-style sets: [`translation-comparison-results.md`](translation-comparison-results.md).
Evidence log: E20 (licences, terms, delivery), E21 (results).

## Summary

- **The open OPUS-MT models translate better than Google's ML Kit in Spanish, French and German** on written text:
  +1.8 to +4.6 chrF, every paired 95% interval above zero, and COMET 0.04 to 0.11 higher.
- **On caption-style text (lowercase, no punctuation) the two are close.** ML Kit is 0.5 ahead on Spanish FLORES and
  they tie in French. OPUS-MT leads in German, by 10 chrF on the unpunctuated speech passages.
- **Punctuation matters more than the engine.** Every engine lost 1 to 15 chrF when it got the same words without
  punctuation. Parakeet (1.1) writes punctuation, so 1.3 should translate Parakeet's punctuated text a sentence at a
  time.
- **Everything is fast enough for captions.** OPUS-MT base with greedy decoding took 35 ms per caption line (p95
  107 ms) on the M4 CPU. ML Kit took 23 ms (p95 59 ms) in an Android emulator. That's Mac speed, not iPhone speed.
- **Only Apple puts up a system pop-up.** Its languages come through a system download sheet or Settings. ML Kit
  and OPUS-MT download under the app's control. ML Kit also sends usage metrics to Google and requires Google
  attribution.
- **Apple wasn't measured yet:** its languages aren't installed on the M4, and only a person can install them
  (asked on #159).

## Results, written text

chrF (0–100, higher is better) on FLORES-200 devtest (1,012 sentences) and WMT24++ speech transcripts (111
passages). COMET (wmt22-comet-da) in brackets. 95% intervals are in the full tables.

| Pair | Set | OPUS-MT base | OPUS-MT tc-big | ML Kit | OPUS-MT base − ML Kit (95% CI) |
|---|---|---|---|---|---|
| en-es | FLORES | 55.0 (0.849) | **56.5** (0.858) | 53.2 (0.805) | +1.8 (+1.4 to +2.1) |
| en-es | speech | 68.9 (0.788) | **69.8** (0.792) | 65.2 (0.723) | +3.6 (+2.8 to +4.4) |
| en-fr | FLORES | 69.8 (0.861) | **72.4** (0.877) | 65.4 (0.802) | +4.4 (+3.9 to +4.9) |
| en-fr | speech | 62.2 (0.753) | **63.3** (0.764) | 59.5 (0.672) | +2.7 (+1.9 to +3.6) |
| en-de | FLORES | **63.6** (0.847) | – | 59.0 (0.759) | +4.6 (+4.1 to +5.2) |
| en-de | speech | **61.3** (0.764) | – | 57.4 (0.656) | +4.0 (+3.0 to +4.9) |

There is no tc-big model for en-de.

## Results, caption-style text

The same sources and references, lowercased with sentence punctuation removed, which is what a caption engine
without punctuation would hand over.

| Pair | Set | OPUS-MT base | OPUS-MT tc-big | ML Kit | OPUS-MT base − ML Kit (95% CI) |
|---|---|---|---|---|---|
| en-es | FLORES | 51.2 (0.784) | **53.1** (0.813) | 51.8 (0.782) | −0.5 (−1.0 to −0.1) |
| en-es | speech | **59.9** (0.638) | 56.5 (0.652) | 58.3 (0.605) | +1.6 (+0.3 to +3.0) |
| en-fr | FLORES | 63.0 (0.784) | **66.5** (0.818) | 62.6 (0.765) | +0.4 (−0.2 to +1.0) |
| en-fr | speech | **54.4** (0.596) | 51.6 (0.603) | 53.8 (0.549) | +0.6 (−0.4 to +1.6) |
| en-de | FLORES | **58.2** (0.751) | – | 56.7 (0.721) | +1.5 (+0.9 to +2.1) |
| en-de | speech | **52.6** (0.553) | – | 42.3 (0.475) | +10.2 (+8.1 to +12.4) |

On the speech passages (median 68 words) there is no punctuation to split on, so these cells also test long
unpunctuated input, which a caption app wouldn't send. tc-big suffers most there.

## Speed, size and delivery

| Engine (en-es) | Median ms per line | p95 ms | Size per pair | Model reaches the phone by | System pop-up |
|---|---|---|---|---|---|
| OPUS-MT base, greedy | 35 | 107 | 82 MB on disk, 69 MB zipped | app download or bundle, our host | none |
| OPUS-MT base, beam 4 | 65 | 198 | same | same | none |
| OPUS-MT tc-big, beam 4 | 102 | 317 | 239 MB, 215 MB zipped | same | none |
| ML Kit | 23 | 59 | 46 MB (both directions) | app-controlled download from Google | none |
| Apple Translation | not run | | system-managed | system sheet or Settings | **yes** |

Speed: 760 EdAcc caption lines, one at a time, two repeats, model load and warm-up excluded. OPUS-MT ran on the
M4 CPU (CTranslate2 int8, 4 threads) with the machine quiet. ML Kit ran in an arm64 Android 15 emulator on the same
M4 while another test was loading the machine (load average 16–28). Under that load OPUS-MT beam 4 measured 111 ms,
so ML Kit's quiet number is probably lower still. Every engine gave identical text on both repeats. Left
untranslated (output equal to input), out of 760: OPUS-MT 5, ML Kit 7, mostly "oh wow" or "okay okay". One of ML
Kit's was a whole 25-word sentence.

ML Kit downloaded en-es in 6 s on the M4's connection. Its folder holds both directions and dictionaries.

## Things we learned on the way

- **Marian models drop sentences from long input.** Fed whole 68-word passages, OPUS-MT left 13 (base) and 21
  (tc-big) of 111 Spanish outputs under 70% of the reference length, against 0 for ML Kit, which splits on its own.
  Translating sentence by sentence fixes it (`translation_eval.split`); the integration must do the same.
- **Greedy decoding costs nothing here.** FLORES 54.8 against 55.0 for beam 4 (COMET 0.847 against 0.849), at about
  half the time.
- **ML Kit can't run in the iOS Simulator on Apple silicon.** MLKitTranslate 8.0.0 has no arm64 Simulator slice, and
  the iOS 26.5 Simulator refuses x86_64 apps. An iOS ML Kit build would need a real device for every test.
- **ML Kit keeps a telemetry queue.** Its `datatransport` event database reached 10 MB over this test's runs.
- One sample line suggests ML Kit softens profanity ("I wouldn't learn shit" became "I wouldn't learn"), while OPUS-MT
  kept it. That's one example, not a measurement, but captions for a hard-of-hearing person should say what was said.
  Worth a check in the iPhone spike.

## Caveats

- Mac CPU and Android emulator, not iPhone. Absolute times will differ on a phone; the ranking of quality won't.
- FLORES is written Wikipedia-style prose. WMT24++ speech passages are real transcripts, but paragraph-length.
- The Spanish references are Latin American (FLORES) and Mexican (WMT24++). The caption-style copies are synthetic.
  Real caption lines (EdAcc) have no reference translation, so they measure speed and failures only.
- Any engine may have seen FLORES or WMT data in training. That can't be checked for Google.
- Firefox's Bergamot wasn't run because there's no arm64 macOS build. It's MPL 2.0 and ships in Firefox on Android,
  so it stays a fallback candidate.

## Recommendation for 1.3

**Use OPUS-MT base models (one per language pair, about 65 MB zipped each), with greedy decoding, translating
Parakeet's punctuated text a sentence at a time. The app downloads them from our own host, behind its own UI.**
Before the ADR, run an iPhone spike: pick the runtime (a Core ML conversion of the Marian model, or CTranslate2 built
for iOS) and measure time per line, memory and battery on a phone.

Why:

1. **Best measured quality.** OPUS-MT beats ML Kit on written text in all three languages, by margins well outside
   the noise. Text from Parakeet is punctuated, so the written-text results are the ones that apply.
2. **No system pop-up, no third party.** The app owns the download and the storage. ML Kit would add Google
   telemetry to the privacy label and Google branding to the screen. Apple's system sheet breaks the no-pop-up rule
   whatever its quality.
3. **The same model on Android.** It fits ADR 0026: one model and one behaviour on both platforms.
4. **Cost:** we ship and maintain a runtime ourselves, and licences need credits (CC BY 4.0 for en-de). The tc-big
   models aren't worth 3× the size for 1 to 3 chrF.

Fallback: if the iPhone spike fails (too slow, too much memory or battery), use ML Kit. It is the turnkey option,
with the attribution and the privacy disclosure. Apple's numbers can be added with one command once its languages
are installed (`swift run --package-path Packages/EngineEval translation-eval ...`). Only a large quality win could
outweigh its system sheet.
