# Scoring Hebrew fairly: one normaliser for both sides, CER beside WER

- **Source:** Marmor et al. (2025), ivrit.ai, Interspeech, [PDF](https://www.isca-archive.org/interspeech_2025/marmor25_interspeech.pdf)
  §4.1 (their leaderboard normalises with Whisper's `BasicTextNormalizer`, which has no Hebrew rules, and they name
  three ways that misleads: full vs defective spelling, digits vs words, verbatim vs clean references); and
  Thennal et al. (2024), *Advocating Character Error Rate for Multilingual ASR Evaluation*,
  [arXiv 2410.07400](https://arxiv.org/abs/2410.07400) (CER tracks human judgement better than WER for
  morphologically rich languages). Gathered in the 2026-10-29 Hebrew speech-data research.
- **What we took:** a Hebrew normaliser applied the same way to the reference and every engine: strip niqqud and
  cantillation, maqaf as a space, geresh and gershayim unified then dropped, number words read as digits (gender and
  construct forms all map to one digit), fillers dropped, bidi marks removed. Report CER beside WER, because one wrong
  prefix letter makes a whole fused Hebrew word wrong in WER. A lenient score folds full and defective spelling; it
  sits beside the strict score, never replaces it. No study was found that measures how much these rules move Hebrew
  WER, so the size of the effect is ours to show.
- **Confidence:** Moderate (one peer-reviewed paper naming the problems, one preprint on CER; the rules themselves
  are ours).
- **Drives:** the Hebrew normaliser (#202, [design](../../perf/hebrew-accuracy-design.md#scoring)) and the Hebrew engine
  test's metrics (#201): CER is the in-house decision metric, WER is for comparing with published numbers.
- **Public use:** Careful ("we score Hebrew on characters as well as words, so a single prefix letter doesn't count
  as a whole wrong word").
