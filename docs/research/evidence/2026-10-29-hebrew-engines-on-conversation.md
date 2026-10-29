# Hebrew engines on conversation and voice notes: Parakeet-He and the small zipformer tie, Apple is four times worse

- **Source:** our own measurement, #201 follow-up, 2026-10-29, M4 Mac mini, macOS 26.5.1:
  [`hebrew-accuracy-comparison.md`](../../perf/hebrew-accuracy-comparison.md), method and caveats in
  [`hebrew-accuracy-design.md`](../../perf/hebrew-accuracy-design.md#conversation-sets-eval-d1-and-eval-whatsapp).
  ivrit.ai [`eval-d1`](https://huggingface.co/datasets/ivrit-ai/eval-d1) @ `7899b04` (conversation, 1.43 h) and
  [`eval-whatsapp`](https://huggingface.co/datasets/ivrit-ai/eval-whatsapp) @ `1267f61` (54 voice notes, 1.18 h),
  gated under the ivrit.ai licence. Same harness, #202 normaliser and engines as
  [evidence `2026-10-29-hebrew-engines-apple-vs-open-models`](2026-10-29-hebrew-engines-apple-vs-open-models.md).
  Every engine ran locally.
- **What we took:** on conversation (eval-d1) Parakeet-He scores **2.4% CER / 5.2% WER** and the ivrit.ai 66M
  streaming zipformer **2.5% / 5.0%**, a tie (95% intervals 2.0–2.9 and 2.1–2.8); ivrit.ai Whisper turbo, the
  reference, is no better at 2.4%. Apple's `DictationTranscriber` he-IL scores **10.4% / 17.8%** (7.8–13.3), about
  four times the open models' character errors, half of its word errors deletions. On voice notes the order holds:
  Parakeet-He 3.8%, zipformer 4.2%, Apple 11.6% CER. Nemotron 3.5 zero-shot: 8.2% on conversation, 20.3% on voice
  notes. The read-speech gap (about 40% fewer character errors) widens to about 75% on conversation.
- **Confidence:** Ours. eval-d1 is one podcast episode with two speakers in 17 consecutive segments, so its interval
  is within-episode only; eval-whatsapp is more varied. All three open models trained on ivrit.ai data, a shared
  domain with these sets. Mac, offline whole files, not iPhone or live latency.
- **Drives:** Hebrew meets the "Seal's own pack if it beats Apple" condition of ADR 0029 and the #200 design, now on
  conversation as well as read speech. Parakeet-He is its own Hebrew fine-tune, not the shared Parakeet pack, so it
  doesn't come free; with the two tied on accuracy, the 66M zipformer (natively streaming, about a tenth the size) is
  the lead candidate for that pack. #201's conclusion stands.
- **Public use:** Careful ("on Hebrew conversation, open models made about a quarter of the character errors of
  Apple's built-in dictation, in our test of one podcast episode and 54 voice notes").
