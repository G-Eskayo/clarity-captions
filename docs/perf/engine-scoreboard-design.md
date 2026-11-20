# Engine Scoreboard Design

Unified view of engine performance across all metrics: captioning accuracy, latency, model size, and speed. Single source of truth for comparing engines across tasks (captions, translation, speakers, voices).

## Row Schema

Each row represents one measurement:
- **task**: Captions, Translation, Speakers, or Voices
- **language** / **language_code**: Human name and ISO 639-1 code
- **engine**: Engine name (e.g., "parakeet-ultra-coreml", "Apple SpeechAnalyzer")
- **platform**: iOS, macOS, Android
- **test_set**: EdAcc, FLEURS, chime6, latency, etc
- **metric_name**: WER, CER, DER, chrF, lag_ms
- **metric_value**: Main measurement (always a decimal 0.0–1.0 for percentages)
- **ci_low** / **ci_high**: 95% confidence interval bounds (decimals)
- **lag_ms**: Latency in milliseconds (populated when relevant)
- **size_bytes** / **zipped_bytes** / **memory_bytes**: Storage and memory footprint
- **speed_x_realtime**: Processing speed as multiple of real time
- **source_ticket**: GitHub issue number (#145, #158, etc)
- **source_file**: Input file name for traceability
- **note**: Free text for edge cases or caveats

## Unit Normalization

All measurements are stored as decimals:
- Percentages: "13.8%" → 0.138
- Confidence intervals: "12.7% – 14.7%" → (0.127, 0.147)
- Bytes: "123 MB" → 123000000, "123 MiB" → 128974848
- Speed: "115.6x" → 115.6

## Source Allowlist

Fixed set of extractable files, skipped if absent:

| File | Task | Extractor |
|---|---|---|
| engine-accuracy-comparison.md | Captions | Overall + Size-options tables |
| language-accuracy-comparison.md | Captions | Per-language tables (Spanish–Portuguese) |
| hebrew-accuracy-comparison.md | Captions | Per-set tables (eval-d1, eval-whatsapp, eval-common) |
| hebrew-coreml-comparison.md | Captions | Core ML build comparison |
| translation-languages-results.json | Translation | Structured per-language results |
| translation-comparison.md | Translation | Speed, size, delivery comparison |
| ear-translation/finish-lag-mac.json | Voices (Ear) | Latency only |
| ear-translation/lag-mac.json | Voices | Latency only (subdirectory) |
| lag-mac.json | Voices | Latency only |
| simulator-iphone.json | Voices | iOS latency only |
| speaker-scoreboard.md | Speakers | Markdown scoreboard results |
| speaker-scoreboard-*.json | Speakers | Build variants (fp16, pal6, pal8, etc) |
| speaker-android-engines.md | Speakers | Android engine comparison |

Absent files are recorded as gaps; malformed present files raise errors.

## Gap vs Malformed Handling

- **Gap**: File absent → recorded in `gaps` dict, build continues
- **Malformed**: File present but parse fails → error raised, specific cell noted
- **Duplicate**: Same (engine, language, test_set, metric) twice → error raised

## Idempotency

Running `build_scoreboard(perf_dir)` twice with the same input always produces the same row list (same order, same values). No randomness or external state.

## Markdown Rendering

One table per task (Captions, Translation, Speakers, Voices). Columns:
- Engine, Language, Test Set, Metric, Value, 95% CI, Lag (ms), Size, Speed

Gaps section at the end if any files were missing.

## JSON Twin

Same data as markdown but machine-readable: array of row objects, plus gaps dict. For downstream pipelines and dashboards.
