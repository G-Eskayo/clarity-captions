# Translation comparison: results (#159)

Generated 2026-10-26 by `python -m translation_eval.cli report`. Design and method: [`translation-comparison-design.md`](translation-comparison-design.md).

Machines: OPUS-MT ran on the M4 Mac mini CPU (CTranslate2 int8, 4 threads, beam 4, sentence by sentence; `opus-mt-greedy` is the base model with beam 1). ML Kit ran in an arm64 Android 15 emulator (Google APIs image) on the same M4, because its iOS frameworks have no arm64 Simulator slice and the iOS 26.5 Simulator no longer runs x86_64 apps. Times are Mac and emulator times, not iPhone times.

Spanish references are Latin American (FLORES `spa_Latn`) and Mexican (WMT24++ `es_MX`); ML Kit and OPUS-MT produce general Spanish. Any dialect gap costs both engines alike.

Timing comes from a separate pass over the caption lines, one engine at a time. OPUS-MT's was taken with the M4 quiet (load average about 5); ML Kit's while another test loaded the machine (load average 16–28), under which OPUS-MT beam 4 measured 111 ms median instead of 65 ms.

- **apple: not run.** Apple's en→es/fr/de languages are *supported, not installed* on the M4 Mac mini, and only a person can install them (system sheet or System Settings → General → Language & Region → Translation Languages). The Translation framework doesn't run in the iOS Simulator. Asked on #159; the Apple rows are added when the languages are in.
- **bergamot: not run.** Firefox's Bergamot runtime has no arm64 macOS build (the `bergamot` wheel is x86_64 only), so it wasn't run in this round. Its models are MPL 2.0 and Firefox ships it on Android, so it stays a candidate.

## en-es

### FLORES-200 devtest, as written

1012 segments in 281 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt-big | opus-mt-tc-big-en-es | 56.5 [55.9–57.1] | 0.858 [0.853–0.863] | best |
| opus-mt | opus-mt-en-es | 55.0 [54.3–55.6] | 0.849 [0.844–0.854] | -1.5 [-1.8 to -1.2] |
| opus-mt-greedy | opus-mt-en-es-greedy | 54.8 [54.2–55.4] | 0.847 [0.842–0.853] | -1.6 [-1.9 to -1.3] |
| mlkit | mlkit-en-es | 53.2 [52.6–53.8] | 0.805 [0.798–0.812] | -3.2 [-3.6 to -2.9] |

### FLORES-200 devtest, caption-style

1012 segments in 281 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt-big | opus-mt-tc-big-en-es | 53.1 [52.4–53.7] | 0.813 [0.806–0.819] | best |
| mlkit | mlkit-en-es | 51.8 [51.2–52.4] | 0.782 [0.774–0.789] | -1.3 [-1.8 to -0.9] |
| opus-mt | opus-mt-en-es | 51.2 [50.6–51.8] | 0.784 [0.777–0.791] | -1.8 [-2.2 to -1.5] |
| opus-mt-greedy | opus-mt-en-es-greedy | 50.9 [50.2–51.5] | 0.782 [0.775–0.789] | -2.2 [-2.6 to -1.8] |

### WMT24++ speech transcripts, as written

111 segments in 111 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt-big | opus-mt-tc-big-en-es | 69.8 [68.3–71.3] | 0.792 [0.777–0.806] | best |
| opus-mt-greedy | opus-mt-en-es-greedy | 68.9 [67.3–70.5] | 0.790 [0.775–0.803] | -0.9 [-1.5 to -0.2] |
| opus-mt | opus-mt-en-es | 68.9 [67.4–70.3] | 0.788 [0.774–0.801] | -0.9 [-1.5 to -0.3] |
| mlkit | mlkit-en-es | 65.2 [63.9–66.7] | 0.723 [0.706–0.739] | -4.5 [-5.3 to -3.8] |

### WMT24++ speech transcripts, caption-style

111 segments in 111 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt | opus-mt-en-es | 59.9 [58.5–61.5] | 0.638 [0.620–0.658] | best |
| opus-mt-greedy | opus-mt-en-es-greedy | 59.8 [58.2–61.4] | 0.642 [0.624–0.660] | -0.1 [-0.7 to +0.5] |
| mlkit | mlkit-en-es | 58.3 [56.4–60.1] | 0.605 [0.586–0.623] | -1.6 [-3.0 to -0.3] |
| opus-mt-big | opus-mt-tc-big-en-es | 56.5 [54.3–58.5] | 0.652 [0.632–0.673] | -3.4 [-5.4 to -1.7] |

### Time per caption line and failure checks (EdAcc lines)

One line at a time (batch size 1), as live captions arrive; model load and the first 5 lines excluded; all repeats pooled. Untranslated: output equals the input. Same text: share of lines identical across repeats 1 and 2.

| Engine | Model | Lines | Median ms | p95 ms | Untranslated | Empty | Same text |
|---|---|---|---|---|---|---|---|
| mlkit | mlkit-en-es | 760 | 23 | 59 | 7 | 0 | 100.0% |
| opus-mt | opus-mt-en-es | 760 | 65 | 198 | 5 | 0 | 100.0% |
| opus-mt-big | opus-mt-tc-big-en-es | 760 | 102 | 317 | 7 | 0 | 100.0% |
| opus-mt-greedy | opus-mt-en-es-greedy | 760 | 35 | 107 | 5 | 0 | 100.0% |

## en-fr

### FLORES-200 devtest, as written

1012 segments in 281 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt-big | opus-mt-tc-big-en-fr | 72.4 [71.5–73.3] | 0.877 [0.872–0.882] | best |
| opus-mt | opus-mt-en-fr | 69.8 [68.9–70.7] | 0.861 [0.856–0.867] | -2.6 [-3.0 to -2.2] |
| mlkit | mlkit-en-fr | 65.4 [64.5–66.3] | 0.802 [0.794–0.810] | -7.0 [-7.6 to -6.4] |

### FLORES-200 devtest, caption-style

1012 segments in 281 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt-big | opus-mt-tc-big-en-fr | 66.5 [65.5–67.5] | 0.818 [0.810–0.825] | best |
| opus-mt | opus-mt-en-fr | 63.0 [62.0–64.0] | 0.784 [0.777–0.792] | -3.5 [-4.0 to -3.1] |
| mlkit | mlkit-en-fr | 62.6 [61.8–63.4] | 0.765 [0.756–0.773] | -3.9 [-4.5 to -3.3] |

### WMT24++ speech transcripts, as written

111 segments in 111 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt-big | opus-mt-tc-big-en-fr | 63.3 [61.7–64.8] | 0.764 [0.748–0.779] | best |
| opus-mt | opus-mt-en-fr | 62.2 [60.6–63.9] | 0.753 [0.737–0.770] | -1.1 [-1.7 to -0.4] |
| mlkit | mlkit-en-fr | 59.5 [58.0–61.1] | 0.672 [0.652–0.690] | -3.8 [-4.5 to -3.1] |

### WMT24++ speech transcripts, caption-style

111 segments in 111 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt | opus-mt-en-fr | 54.4 [53.0–55.9] | 0.596 [0.580–0.612] | best |
| mlkit | mlkit-en-fr | 53.8 [52.2–55.5] | 0.549 [0.534–0.565] | -0.6 [-1.6 to +0.4] |
| opus-mt-big | opus-mt-tc-big-en-fr | 51.6 [49.6–53.6] | 0.603 [0.585–0.622] | -2.8 [-4.6 to -1.2] |

### Time per caption line and failure checks (EdAcc lines)

One line at a time (batch size 1), as live captions arrive; model load and the first 5 lines excluded; all repeats pooled. Untranslated: output equals the input. Same text: share of lines identical across repeats 1 and 2.

| Engine | Model | Lines | Median ms | p95 ms | Untranslated | Empty | Same text |
|---|---|---|---|---|---|---|---|
| mlkit | mlkit-en-fr | 760 | 19 | 54 | 7 | 0 | 100.0% |

## en-de

### FLORES-200 devtest, as written

1012 segments in 281 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt | opus-mt-en-de | 63.6 [62.7–64.5] | 0.847 [0.840–0.853] | best |
| mlkit | mlkit-en-de | 59.0 [58.1–59.8] | 0.759 [0.749–0.769] | -4.6 [-5.2 to -4.1] |

### FLORES-200 devtest, caption-style

1012 segments in 281 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt | opus-mt-en-de | 58.2 [57.3–59.0] | 0.751 [0.741–0.761] | best |
| mlkit | mlkit-en-de | 56.7 [55.8–57.5] | 0.721 [0.710–0.732] | -1.5 [-2.1 to -0.9] |

### WMT24++ speech transcripts, as written

111 segments in 111 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt | opus-mt-en-de | 61.3 [59.8–62.9] | 0.764 [0.747–0.781] | best |
| mlkit | mlkit-en-de | 57.4 [55.8–59.0] | 0.656 [0.633–0.676] | -4.0 [-4.9 to -3.0] |

### WMT24++ speech transcripts, caption-style

111 segments in 111 bootstrap groups, scored on the segments every engine finished. chrF 0 to 100, higher is better; COMET (wmt22-comet-da) 0 to 1. Brackets: 95% CI. "vs best": paired chrF difference to the top engine, with its 95% CI.

| Engine | Model | chrF | COMET | vs best |
|---|---|---|---|---|
| opus-mt | opus-mt-en-de | 52.6 [51.1–54.1] | 0.553 [0.533–0.573] | best |
| mlkit | mlkit-en-de | 42.3 [39.9–44.8] | 0.475 [0.456–0.494] | -10.2 [-12.4 to -8.1] |

### Time per caption line and failure checks (EdAcc lines)

One line at a time (batch size 1), as live captions arrive; model load and the first 5 lines excluded; all repeats pooled. Untranslated: output equals the input. Same text: share of lines identical across repeats 1 and 2.

| Engine | Model | Lines | Median ms | p95 ms | Untranslated | Empty | Same text |
|---|---|---|---|---|---|---|---|
| mlkit | mlkit-en-de | 760 | 24 | 60 | 6 | 0 | 100.0% |

## Model size per language pair

| Model | On disk | Zipped | How measured | Licence |
|---|---|---|---|---|
| mlkit-en-de | 47 MB | – | ML Kit language folder on the device (du, both directions) | ML Kit terms |
| mlkit-en-es | 46 MB | – | ML Kit language folder on the device (du, both directions) | ML Kit terms |
| mlkit-en-fr | 45 MB | – | ML Kit language folder on the device (du, both directions) | ML Kit terms |
| opus-mt-en-de | 79 MB | 63 MB | CTranslate2 int8 folder (model.bin, vocabularies, SentencePiece models) | CC BY 4.0 |
| opus-mt-en-es | 82 MB | 69 MB | CTranslate2 int8 folder (model.bin, vocabularies, SentencePiece models) | Apache 2.0 |
| opus-mt-en-fr | 79 MB | 62 MB | CTranslate2 int8 folder (model.bin, vocabularies, SentencePiece models) | Apache 2.0 |
| opus-mt-tc-big-en-es | 239 MB | 215 MB | CTranslate2 int8 folder (model.bin, vocabularies, SentencePiece models) | CC BY 4.0 |
| opus-mt-tc-big-en-fr | 236 MB | 212 MB | CTranslate2 int8 folder (model.bin, vocabularies, SentencePiece models) | CC BY 4.0 |

## How the language model gets onto the device

| Engine | Who downloads | System UI | Notes |
|---|---|---|---|
| Apple Translation | the system | **yes**: a system download sheet (`prepareTranslation()` or first use), or the person installs it in Settings | The app can't download silently, restyle the sheet or delete a language. Languages are shared with Apple's Translate app. |
| ML Kit | the app (`downloadModelIfNeeded`, `deleteDownloadedModel`) | none | Downloaded from Google's servers. en-es took 6 s on the M4's connection and added 45 MB. The SDK sends usage metrics to Google (it keeps a `datatransport` event database) and needs Google attribution. |
| OPUS-MT | the app | none | Bundled, or downloaded from a host we choose; no third-party SDK or metrics. Needs a runtime we ship ourselves (CTranslate2, Marian or a Core ML conversion on iOS). |
