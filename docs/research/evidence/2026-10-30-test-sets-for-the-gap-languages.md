# Held-out test sets for new caption languages: read speech is clean everywhere, conversation almost nowhere

- **Sources:** dataset cards and licence pages read 2026-10-30: [FLEURS](https://huggingface.co/datasets/google/fleurs)
  (CC BY 4.0), Common Voice v27 and Spontaneous Speech v5 stats
  ([cv-dataset](https://github.com/common-voice/cv-dataset)), [VoxPopuli](https://huggingface.co/datasets/facebook/voxpopuli)
  (CC0), [IndicVoices](https://huggingface.co/datasets/ai4bharat/IndicVoices) (CC BY 4.0, gated),
  [LOTUSDIS](https://huggingface.co/datasets/nectec/LOTUSDIS) (CC BY-SA 4.0), [JuzneVesti-SR](http://hdl.handle.net/11356/1679)
  (CC BY-SA 4.0), [GigaSpeech 2](https://huggingface.co/datasets/speechcolab/gigaspeech2),
  [CASABLANCA](https://huggingface.co/datasets/UBC-NLP/Casablanca), [NaijaVoices](https://huggingface.co/datasets/naijavoices/naijavoices-dataset),
  [PELCRA for BIGOS](https://huggingface.co/datasets/pelcra/pl-asr-pelcra-for-bigos). Notes, with speaker counts
  (Ethnologue 2026 via Wikipedia) and Israel's language figures:
  [`testsets-speakers.md`](../languages-batch/testsets-speakers.md).
- **What we took:** commercially clean conversational or unscripted test sets exist only for the Indic languages
  (IndicVoices, 5 h each), Thai (LOTUSDIS meetings), Serbian (JuzneVesti interviews), Russian (2.2 h of Common Voice
  Spontaneous) and, as parliament speech, 16 European languages (VoxPopuli). Arabic (all dialects), Vietnamese,
  Indonesian, Turkish, Greek and the African languages have only non-commercial, research-only or paid conversational
  sets; GigaSpeech 2's terms bind a for-profit employer by name. FLEURS and Common Voice give clean read-speech sets
  everywhere (Common Voice now only via Mozilla Data Collective, no re-hosting). Arabic is the first language of about
  2.1M Israelis (21%), Russian of 1.2–1.5M.
- **Confidence:** Strong for the licences read on the cards; Moderate for test hours estimated from Common Voice clip
  counts and for speaker figures where the language's definition is disputed (Arabic, Persian, Hindi, Thai, Swahili).
- **Drives:** #236's test-data Decision and each language's measurement ticket.
- **Public use:** Internal (licence analysis); speaker counts Yes with their source.
