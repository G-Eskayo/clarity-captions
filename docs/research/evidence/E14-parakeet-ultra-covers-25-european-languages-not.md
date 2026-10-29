# E14. Parakeet Ultra covers 25 European languages, not just English

- **Source:** Parakeet Ultra model card (read from a mirror, [matenek/parakeet-ultra](https://huggingface.co/matenek/parakeet-ultra);
  the `moondream/parakeet-ultra` page didn't load on 2026-10-26) and [Spokenly on Parakeet v3](https://spokenly.app/blog/parakeet-models).
- **What we took:** Ultra is a post-training of Parakeet TDT 0.6B v3 (25 European languages, language detected
  automatically). Card figures: 25-language FLEURS WER 9.55% (v3 11.62%), English Open ASR 5.80% (v3 6.26%).
- **Confidence:** Moderate (card figures via a mirror; not our measurement yet).
- **Drives:** ADR 0026; the 1.2 languages plan may use Parakeet for European languages instead of Apple's engine,
  pending the FLEURS test. Challenges the "Ultra is English-tuned" risk row in the engine-switch design.
- **Public use:** Careful (cite as the model card's numbers, not ours).
