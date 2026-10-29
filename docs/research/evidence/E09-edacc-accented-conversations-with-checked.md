# E9. EdAcc: accented conversations with checked transcripts

- **Source:** Sanabria, Bogoychev, Markl, Carmantini, Klejch & Bell (2023), *The Edinburgh International Accents of
  English Corpus: Towards the Democratization of English ASR*, ICASSP. [arXiv 2303.18110](https://arxiv.org/abs/2303.18110) ·
  [Edinburgh DataShare, doi:10.7488/ds/7914](https://doi.org/10.7488/ds/7914) (handle 10283/8983) ·
  Hugging Face mirror [`edinburghcstr/edacc`](https://huggingface.co/datasets/edinburghcstr/edacc) (test + validation,
  6.95 GB parquet, 19,137 segments, 32.7 h after segmentation, 32 accent groups, 122 speakers).
- **License:** CC BY-SA (the current DataShare record ships `CC_BY_SA_license_text.txt`; checked 2026-10-21). An earlier
  DataShare record was withdrawn over a license change, so this current record is the one we rely on. The Hugging Face
  card states no license of its own; we treat the mirror as carrying the DataShare license.
- **What we took:** two-person conversations, human transcripts and per-speaker accent and first-language labels: the
  closest public match to Seal's sit-down use. The paper reports every model degrading on accents (the best, Whisper
  large, averaged 19.7% WER versus 2.7% on clean US read speech), worst on Jamaican, Indonesian, Nigerian and Kenyan
  English.
- **Handling:** downloaded with the owner's approval (2026-10-21) to the 2012 Mac mini only; the audio never goes in the
  repo (ignore rules) or on any public page. Only aggregate scores are published.
- **Confidence:** Strong (peer-reviewed corpus).
- **Drives:** #145 engine accuracy test ([design](../perf/engine-accuracy-design.md), [results](../perf/engine-accuracy-comparison.md)).
- **Public use:** Careful (cite the corpus and aggregate WER; never quote or play its audio).
