# E21. Translation comparison: Apple's Translation framework beats OPUS-MT and ML Kit in Spanish, French and German

- **Source:** our own measurement, [docs/perf/translation-comparison.md](../perf/translation-comparison.md)
  (#159 "[E] Translation comparison test: Apple vs ML Kit vs open models, before 1.3"). FLORES-200 devtest (1,012
  sentences) and WMT24++ speech transcripts (111 passages), each as written and in a caption-style copy (lowercase,
  unpunctuated); 760 EdAcc caption lines for speed. chrF and COMET (wmt22-comet-da), 95% bootstrap CIs over documents.
  Apple's Translation framework on the M4 Mac mini (macOS 26.5.1, languages installed in Settings); OPUS-MT on the
  same machine's CPU (CTranslate2 int8, sentence by sentence); ML Kit 17.0.3 in an arm64 Android 15 emulator on the
  same machine.
- **What we took:** **Apple was the most accurate engine in every cell.** chrF on FLORES as written: Apple **56.8**,
  OPUS-MT base 55.0, ML Kit 53.2 (es); **73.2**, 69.8, 65.4 (fr); **68.2**, 63.6, 59.0 (de). On speech transcripts:
  **71.6**, 68.9, 65.2 (es); **65.3**, 62.2, 59.5 (fr); **64.3**, 61.3, 57.4 (de). Apple's lead over OPUS-MT base was
  +1.8 to +4.5 chrF on written text and +3.6 to +7.9 on caption-style text, every paired 95% CI above zero; COMET
  agrees (e.g. FLORES de 0.883 vs 0.847 vs 0.759). It also beat the larger OPUS-MT tc-big models (+0.3 to +2.0).
  Apple lost only 2 to 7 chrF on caption-style input, where the others lost up to 15 (German caption-style speech:
  Apple 60.5, OPUS-MT 52.6, ML Kit 42.3). Speed per caption line, en-es, machine quiet: Apple **59 ms median, 89 ms
  p95**; OPUS-MT greedy 35 / 107 ms; ML Kit 23 / 59 ms in the emulator under heavier load. Apple's en→es languages
  take about 286 MB of system assets (about 221 MB zipped), held by the system, not the app; each further language
  in its family adds about 80 MB. Among the engines the app would download itself, OPUS-MT beat ML Kit on written
  text in all three languages (+1.8 to +4.6 chrF). Greedy decoding kept OPUS-MT's quality (FLORES 54.8, COMET 0.847)
  at half the time. Marian models silently drop sentences from long multi-sentence input unless fed a sentence at a
  time.
- **Confidence:** Ours. Strong for the ranking on written and caption-style text (all paired CIs exclude zero in all
  three languages; Apple vs tc-big on Spanish FLORES only just). Mac and emulator, not iPhone; Spanish references are
  Latin American; any engine may have seen FLORES or WMT data in training.
- **Drives:** the 1.3 translation engine (recommendation: Apple's Translation framework under ADR 0026, with the
  system download sheet as a decision for Gil; OPUS-MT base as the cross-platform engine and fallback), and the rule
  to translate Parakeet's punctuated text.
- **Public use:** Careful ("in our test on public benchmarks, Apple's on-device translation was the most accurate of
  the engines we tried in Spanish, French and German, ahead of an open model and Google's on-device ML Kit").
