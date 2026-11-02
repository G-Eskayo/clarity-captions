# Seal Speak, issue 236: held-out test sets and speaker counts for 26 candidate caption languages

Accessed 2026-10-30 unless noted. Read-only research: no dataset audio was downloaded. I fetched only small public JSON stats files from `github.com/common-voice/cv-dataset`. These are metadata files, not audio.

Tiers: **Established** means a primary source (dataset card, paper or official stats) was read directly. **Contested** means sources disagree. **Speculative** means it is inferred or comes from a secondary summary. **Unknown** means no source was found.

Licence flags used below:
- **NC**: non-commercial only.
- **ND**: no derivatives.
- **SA**: share-alike.
- **GATED**: you must accept terms before download.
- **RESEARCH-ONLY**: custom terms limited to research or education.
- **PAID**: a paid licence is needed.
- **MDC-ToS**: Mozilla Data Collective terms of service, which forbid re-hosting the dataset and identifying speakers.

A paid company scores engines here, so every NC, ND, research-only or LDC row needs a decision from the owner. Using NC data for "internal evaluation only" by a for-profit is a grey area. NC licences restrict *use*, not only redistribution. Treat NC as **not cleared** unless the licensor confirms otherwise.

---

## 1. Multilingual candidates (checked first)

| Dataset | Licence (quoted) | Style | Test split | Gated | Tier |
|---|---|---|---|---|---|
| **FLEURS** (google/fleurs) https://huggingface.co/datasets/google/fleurs | `cc-by-4.0` (card YAML) | **Read** (FLoRes Wikipedia sentences; 3 native speakers per sentence) | 350 sentences per language. 283 h test across 102 languages, about 2.8 h per language on average (my arithmetic from the paper's totals). Test speakers are disjoint from train. https://arxiv.org/abs/2205.12446 | No | Established |
| **Common Voice Scripted Speech v27.0** (cut-off 2026-09-11) https://github.com/common-voice/cv-dataset/blob/main/datasets/scripted-speech/cv-corpus-27.0-2026-09-11.json | CC0-1.0 on MDC listings, plus MDC-ToS (since Oct 2025 the only distribution channel is Mozilla Data Collective, login required) https://discourse.mozilla.org/t/exciting-news-mozilla-data-collective/145191 | **Read** (crowd, phone or laptop mics) | See per-language table (§3) | Login plus ToS | Established |
| **Common Voice Spontaneous Speech v5.0** (cut-off 2026-09-11) https://github.com/common-voice/cv-dataset/blob/main/datasets/spontaneous-speech/sps-corpus-5.0-2026-09-11.json | CC0-1.0 plus MDC-ToS ("forbidden to re-host or re-share this dataset"; "forbidden to attempt to determine the identity of speakers") https://www.mozillafoundation.org/en/blog/common-voice-navbar-changes-and-spontaneous-speech | **Spontaneous monologue** (answers to open questions such as "tell me about a hobby"). It is not dialogue. | Of our languages, only **ru** has a test bucket: 2.17 h, 12 speakers. tr 0.28 h, nl 0.35 h, th 0.08 h, sw 0.33 h and am about 0 h total all have empty test buckets. el-CY (Cypriot Greek) has a 2.88 h test from only 3 speakers. | Login plus ToS | Established (stats JSON read directly) |
| **VoxPopuli** https://huggingface.co/datasets/facebook/voxpopuli | "The dataset is distributet under CC0 license, see also European Parliament's legal notice for the raw data." | **Parliament**: semi-spontaneous, often prepared speeches, interpreted register | Transcribed ASR for 16 langs: en, de, fr, es, **pl**, it, **ro**, hu, **cs**, **nl**, fi, hr, sk, sl, et, lt. Per-language test hours are not on the card. | No | Licence and languages Established; test hours Unknown |
| **Multilingual LibriSpeech** https://huggingface.co/datasets/facebook/multilingual_librispeech | CC BY 4.0 | **Read audiobooks** | nl 12.76 h, pl 2.14 h (others are not our languages) | No | Established |
| **Speech-MASSIVE** https://huggingface.co/datasets/FBK-MT/Speech-MASSIVE-test | "All datasets are licensed under the CC-BY-NC-SA-4.0 license." **NC** | Read voice-assistant commands (spoken MASSIVE text) | ar-SA 3.23 h, nl 3.30, pl 3.21, ru 3.44, tr 3.00, vi 3.23 | **GATED** | Established. Style is Speculative (card silent; read by construction) |
| **YODAS2** https://huggingface.co/datasets/espnet/yodas2 | Card lists `cc-by-3.0`; "only consisted of videos with CC licenses" | YouTube (mixed, much spontaneous) | **No test split**; labels partly auto-captions | No | Established. Not usable as a clean test set |
| **Granary** (NVIDIA) https://huggingface.co/datasets/nvidia/Granary | `cc-by-4.0` | Pseudo-labelled VoxPopuli, YODAS, YTC, LibriLight | Training corpus; no human test set | No | Established. Not a test set |
| **Emilia / Emilia-YODAS** https://huggingface.co/datasets/amphion/Emilia-Dataset | Emilia: "CC-BY-NC" (**NC**); Emilia-YODAS: "CC-BY" | Spontaneous in-the-wild | Only en, zh, de, fr, ja, ko. **None of our languages.** | **GATED** | Established |
| **People's Speech** https://huggingface.co/datasets/MLCommons/peoples_speech | "CC-BY-SA and CC-BY 4.0" | Mixed | **English only** | No | Established |
| **GigaSpeech 2** https://huggingface.co/datasets/speechcolab/gigaspeech2 | Card metadata Apache-2.0, but the access terms say use is limited to "**non-commercial research and educational purposes**". The terms bind a for-profit employer too. **NC / RESEARCH-ONLY** | YouTube, spontaneous; test sets human-transcribed and "challenging and realistic" | **th test 10.0 h, id 10.0 h, vi 11.0 h** | **GATED** | Established |
| **IARPA Babel** (LDC) e.g. https://catalog.ldc.upenn.edu/LDC2017S05 (Swahili), https://catalog.ldc.upenn.edu/LDC2016S13 (Tagalog) | LDC per-pack agreements in For-Profit, Non-Member and Not-For-Profit variants. **PAID** | **Conversational telephone** (8 kHz) plus scripted | Packs exist for Swahili, Tagalog, Bengali and others. Turkish, Vietnamese, Amharic and Telugu packs were not confirmed in my search. | LDC purchase | Swahili and Tagalog Established; others Unknown |
| **CallHome / CallFriend** (LDC) | **PAID**, LDC | Telephone conversation | CallHome Egyptian Arabic about 17 h total (via the Arab Voices table https://arxiv.org/html/2601.13319) | LDC | Speculative (not checked on the LDC page) |

**Takeaway.** No free, commercially clean, *conversational* (dialogue) test set covers most of these languages. The commercially clean options are:
- FLEURS and Common Voice Scripted, which are read speech.
- VoxPopuli, which is parliament speech.
- CV Spontaneous, which is monologue and so small that only Russian is usable.
- A handful of language-specific CC BY or CC BY-SA corpora, listed in §2.

Most real conversational sets are NC, research-only or LDC-paid.

---

## 2. Per-language best test sets

Column (1) is the best conversational or spontaneous set. Column (2) is the read fallback. FLEURS is always CC BY 4.0, read, about 350 sentences (about 2 to 3 h), not gated. CV27 is CC0 plus MDC-ToS, read; approximate test hours are in §3.

| Language | (1) Conversational / spontaneous: name, licence, test size, style, gated | (2) Read fallback | Tier |
|---|---|---|---|
| **Arabic (MSA / pan-Arab)** | **MASC** (YouTube, about 1,000 h, clean and noisy test splits, multi-dialect) https://ieee-dataport.org/open-access/massive-arabic-speech-corpus-masc. Licence is **contested**: the HF mirror says `cc-by-nc-4.0`, the card says "CC 4.0", and a "Fix license metadata" PR is open. **MGB-2** (Al Jazeera broadcast, about 1,200 h train) https://huggingface.co/datasets/QCRI/mgb2: "QCRI-ALT Corpus License Agreement", a non-exclusive **research-use** licence, **GATED**. **SADA** (Saudi TV, about 10 h test) https://ieee-dataport.org/node/14747: **CC BY-NC-SA 4.0**. **Maqsam call-centre benchmark** (132 h, 6 dialects, telephone) https://arxiv.org/abs/2403.04280: release URL and licence **Unknown**. | FLEURS ar_eg (428 test utterances; despite the code it is MSA read by Egyptian speakers); CV27 ar about 12.3 h | Established, except the MASC licence (Contested) and Maqsam (Unknown) |
| **Arabic: Egyptian** | **CASABLANCA** Egypt subset https://huggingface.co/datasets/UBC-NLP/Casablanca: `cc-by-nc-nd-4.0` (**NC, ND**); TV-series dialogue; only validation and test are released. **MGB-3** (about 16 h Egyptian YouTube broadcast) http://www.mgb-challenge.org/MGB-3.html: licence "Available on MGB website", **Unknown**. **CallHome Egyptian** (LDC, **PAID**, telephone). **EGCON** (2.3 h conversational; licence Unknown) via https://arxiv.org/html/2601.13319 | FLEURS ar_eg | Casablanca Established; others Unknown or Speculative |
| **Arabic: Levantine / Palestinian** | **CASABLANCA** Palestine (1.33k rows) and Jordan subsets: **cc-by-nc-nd-4.0** (**NC, ND**). **DiaSet** (Palestinian YouTube conversations and interviews) https://aclanthology.org/2024.lrec-main.436: the paper header shows CC BY-NC 4.0, but whether ASR-aligned audio is released is **Unknown**. The Arab Voices 2026 survey lists **no Palestinian-labelled ASR dataset**. | CV27 ar (mixed dialects, read) | Established for Casablanca; DiaSet Unknown |
| **Persian** | **PSRB** (PartAI) https://huggingface.co/datasets/PartAI/PSRB: "made available for research and educational purposes only" (**RESEARCH-ONLY**). Only a 1-hour public sample (344 clips) with a `spontaneous` flag; sources are news, film, podcast and phone. **VirgoolInformal** (informal; data CC-0 per repo listing; size and test split Unknown) https://awesome.ecosyste.ms/projects/github.com%2Fmahtafetrat%2Fvirgoolinformal-speech-dataset | CV27 fa about 11.7 h (4,668 speakers in total corpus); FLEURS fa_ir (871 utts) | PSRB Established; Virgool Speculative |
| **Turkish** | No open conversational test set found. CV-SPS tr has an empty test bucket (0.28 h total). **MediaSpeech** tr (10 h media, HF mirror says CC BY 4.0, unverified at source). **Babel Turkish** (LDC, **PAID**, telephone; pack not confirmed). Speech-MASSIVE tr 3.0 h is read, NC. | CV27 tr about 12.7 h; FLEURS tr_tr | Contested (MediaSpeech licence); gap Established |
| **Russian** | **CV Spontaneous Speech 5.0 ru**: test **2.17 h, 12 speakers**, CC0 plus MDC-ToS, spontaneous monologue. This is the only of our languages with a usable CV-SPS test. **Golos farfield** test 1.4 h (smart-speaker commands, not conversational) https://www.openslr.org/114: custom **Sber licence** PDF (review before commercial use). **Russian Open STT** (radio, YouTube, calls): licence **Unknown/Contested** (often described as CC BY-NC; not verified). | CV27 ru about 14.9 h; Golos crowd test 11.2 h (read); FLEURS ru_ru | CV-SPS Established; Golos licence Contested; Open STT Unknown |
| **Ukrainian** | No open conversational test set found. **VOA Ukrainian broadcast** (about 398 h, Zenodo) https://zenodo.org/record/7404392: licence not confirmed (Unknown). Hutsul-dialect set (UNLP 2026) https://aclanthology.org/2026.unlp-1.16/ is dialectal. | CV27 uk about 14.1 h. "cv10-uk-testset-clean" (human-checked CV10 test) https://awesome.ecosyste.ms/projects/github.com%2Fegorsmkv%2Fcv10-uk-testset-clean. FLEURS uk_ua | Gap Established; VOA licence Unknown |
| **Polish** | **PELCRA for BIGOS** (SpokesMix / SpokesBiz / DiaBiz: "spontaneous and conversional speech and phone-based customer interactions") https://huggingface.co/datasets/pelcra/pl-asr-pelcra-for-bigos: "Creative Commons By Attribution Non Commercial No Derivates" (**NC, ND, GATED**). Median WER is about 31% here vs about 14% on read speech (https://huggingface.co/blog/michaljunczyk/introducing-polish-asr-leaderboard). **ParlaSpeech-PL** (parliament, about 1,010 h): **CC BY-SA 4.0**, clean; no official test split found https://clarinsi.github.io/parlaspeech. **VoxPopuli pl**: CC0. | BIGOS v2 (CC BY-SA 4.0 overall, per-source terms) https://huggingface.co/datasets/amu-cai/pl-asr-bigos-v2; MLS pl 2.14 h; CV27 pl about 12.8 h; FLEURS | Established |
| **Dutch** | **Corpus Gesproken Nederlands (CGN)** (about 900 h, includes spontaneous face-to-face and telephone) https://taalmaterialen.ivdnt.org/?p=1290. The standard licence is free but limited to research and non-commercial products; a **commercial licence** is separately available. **VoxPopuli nl** (CC0, parliament) is the clean option. | MLS nl 12.76 h (read audiobooks); CV27 nl about 14.9 h; FLEURS nl_nl | Established (CGN commercial price Unknown) |
| **Greek** | No open conversational Greek test set found. CV-SPS **el-CY** (Cypriot Greek) test 2.88 h but **only 3 speakers**: dialect mismatch and too few speakers. | FLEURS el_gr (650 utts); CV27 el about 2.1 h | Gap Established |
| **Romanian** | **VoxPopuli ro** (CC0, parliament). **RO-N3WS** (126 h incl. podcast conversation and film dialogue) https://arxiv.org/pdf/2603.02368: licence and release **Unknown**. | RSC (100 h read, 164 speakers; licence Unknown) https://aclanthology.org/2020.lrec-1.814; CV27 ro about 4.7 h; FLEURS ro_ro | VoxPopuli Established; others Unknown |
| **Czech** | **ParlaSpeech-CZ** (parliament, about 1,218 h) https://b2find.eudat.eu/dataset/bddb5779-1bfa-5e6d-8fe7-3ed071e86955: **CC BY-SA 4.0**; no official test split (would need our own held-out slice). **VoxPopuli cs** CC0. | CV27 cs about 11.8 h; FLEURS cs_cz (723 utts) | Established |
| **Hindi** | **IndicVoices** hi test **5 h, 63 speakers** https://huggingface.co/datasets/ai4bharat/IndicVoices: "released under the CC BY 4.0", **GATED** (click-through). Corpus mix: 76% extempore, 15% conversational, 8% read; the test-split style mix is not stated. Test table: https://ar5iv.labs.arxiv.org/html/2403.01926. **Lahaja** (12.5 h, 132 speakers, read plus extempore) https://huggingface.co/datasets/ai4bharat/Lahaja: CC BY 4.0 in text vs `mit` in metadata, **GATED**. | Kathbath hi (read; CC0 per HF vs CC BY-SA per AIKosh, **Contested**) https://huggingface.co/datasets/ai4bharat/Kathbath; CV27 hi about 4.8 h; FLEURS hi_in | IndicVoices Established |
| **Urdu** | **IndicVoices ur** test **5 h, 99 speakers** (CC BY 4.0, GATED). Indian Urdu speakers, not Pakistani. | CV27 ur about 6.0 h; FLEURS ur_pk | Established |
| **Bengali** | **IndicVoices bn** test **5 h, 125 speakers** (CC BY 4.0, GATED); Indian (West Bengal) speakers. Babel Bengali (LDC, PAID, telephone) https://catalog.ldc.upenn.edu/docs/LDC2016S08/README_FIRST.txt | Kathbath bn; CV27 bn about 11.4 h; FLEURS bn_in | Established |
| **Tamil** | **IndicVoices ta** test **5 h, 195 speakers** (CC BY 4.0, GATED) | Kathbath ta; CV27 ta about 21 h; FLEURS ta_in | Established |
| **Telugu** | **IndicVoices te** test **5 h, 107 speakers** (CC BY 4.0, GATED) | Kathbath te; FLEURS te_in (CV27 te only about 0.1 h) | Established |
| **Marathi** | **IndicVoices mr** test **5 h, 100 speakers** (CC BY 4.0, GATED) | Kathbath mr; CV27 mr about 3.1 h; FLEURS mr_in | Established |
| **Vietnamese** | **GigaSpeech 2 vi** test 11.0 h (YouTube, spontaneous): **NC / RESEARCH-ONLY, GATED**. **VietSuperSpeech** (YouTube, 26.7 h dev+test) https://arxiv.org/abs/2603.01894: licence **Unknown**. **VietMed** (medical conversation): licence **Unknown**. **Bud500**: CC BY-NC-SA 4.0 (NC). | FLEURS vi_vn; CV27 vi about 1.8 h | GigaSpeech2 Established; others Unknown |
| **Indonesian** | **GigaSpeech 2 id** test 10.0 h (**NC / RESEARCH-ONLY, GATED**). **Podcast Homostoria** (11 h spontaneous podcast, Indonesian with English/Javanese code-switching) https://datacollective.mozillafoundation.org/datasets/cmiepnyu1001jo207hzslvb5m: **CC BY-SA 4.0** per listing; no test split, so the whole set would be the held-out set. | FLEURS id_id; CV27 id about 4.1 h | Homostoria Speculative (listing seen only via search snippet) |
| **Thai** | **LOTUSDIS** (NECTEC far-field meeting dialogue, 3 people per session) https://huggingface.co/datasets/nectec/LOTUSDIS: **cc-by-sa-4.0**, not gated. **Test 13.3 h** multi-channel, which is about 2.6 h of unique sessions over 9 mics; 11 sessions, 12 participant entries. https://arxiv.org/html/2509.18722v1. **This is the best clean conversational find in this report.** GigaSpeech 2 th test 10 h (NC). | CV27 th about 12.9 h; FLEURS th_th | Established |
| **Filipino / Tagalog** | **Babel Tagalog** (LDC2016S13, telephone conversation, **PAID**) https://catalog.ldc.upenn.edu/LDC2016S13. **PixelML sea-asr-ph conversational split** (2.68 h, 150 CC BY YouTube videos, Apache-2.0) https://huggingface.co/PixelML/sea-asr-ph. **References are machine-generated (Qwen3-ASR plus omniASR agreement), not human, so they are unsuitable as ground truth.** | FLEURS fil_ph (964 utts). Common Voice has no tl locale. | Established |
| **Swahili** | **Babel Swahili** (LDC2017S05, about 350 h telephone, **PAID**, For-Profit agreement available). CV-SPS sw has an empty test bucket. | CV27 sw about 17.9 h; FLEURS sw_ke; ALFFA sw (read and broadcast, about 1.8 h test; licence contested between MIT and CC BY-SA 3.0) https://openslr.org/25/ | Babel Established; ALFFA Contested |
| **Amharic** | None found. Babel Amharic not confirmed. | FLEURS am_et (516 utts); ALFFA am https://openslr.org/25/ (licence Contested); CV27 am about 0.5 h | Gap Established |
| **Hausa** | **NaijaVoices** https://huggingface.co/datasets/naijavoices/naijavoices-dataset: "licensed under the CC BY-NC-SA 4.0 license" (**NC, GATED**); commercial waivers via membership tiers; about 605 h, test about 0.3%; style not stated. | FLEURS ha_ng; CV27 ha about 1.0 h | Established |
| **Yoruba** | **NaijaVoices** yo: same terms as Hausa (**NC, GATED**) | FLEURS yo_ng; CV27 yo about 1.8 h | Established |
| **Serbian** | **JuzneVesti-SR** (interview show "15 minuta", about 50.6 h, 80:10:10 split, so about 5 h test) http://hdl.handle.net/11356/1679: **CC BY-SA 4.0**. Interview speech is close to conversational. **ParlaSpeech-RS** (896 h parliament, CC BY-SA 4.0). | FLEURS sr_rs; CV27 sr about 1.8 h | Established |
| **Bulgarian** | None found (VoxPopuli has no transcribed bg; Granary's bg_voxpopuli is pseudo-labelled). | FLEURS bg_bg (658 utts); CV27 bg about 5.3 h | Gap Established |

---

## 3. Common Voice v27.0 scripted test split (from the official stats JSON, accessed 2026-10-30)

Test hours ≈ test clips × corpus-average clip length (my estimate). Speakers = all contributors in the locale, not test-only.

| loc | test clips | ≈test h | speakers | loc | test clips | ≈test h | speakers |
|---|---|---|---|---|---|---|---|
| ar | 10,606 | 12.3 | 1,679 | hi | 3,402 | 4.8 | 485 |
| fa | 10,755 | 11.7 | 4,668 | ur | 5,074 | 6.0 | 506 |
| tr | 11,874 | 12.7 | 1,840 | bn | 9,408 | 11.4 | 23,019 |
| ru | 10,328 | 14.9 | 3,767 | ta | 12,241 | 21.0 | 984 |
| uk | 10,956 | 14.1 | 1,181 | te | 98 | 0.1 | 75 |
| pl | 10,096 | 12.8 | 3,477 | mr | 1,800 | 3.1 | 107 |
| nl | 12,257 | 14.9 | 1,892 | vi | 1,593 | 1.8 | 419 |
| el | 1,842 | 2.1 | 456 | id | 3,711 | 4.1 | 678 |
| ro | 4,113 | 4.7 | 464 | th | 11,064 | 12.9 | 7,997 |
| cs | 9,493 | 11.8 | 1,146 | sw | 12,271 | 17.9 | 1,525 |
| am | 281 | 0.5 | 56 | ha | 829 | 1.0 | 64 |
| yo | 1,096 | 1.8 | 138 | sr | 1,942 | 1.8 | 187 |
| bg | 3,517 | 5.3 | 155 | he | 937 | 1.2 | 60 |
| tl | n/a | n/a | n/a | | | | |

Source: https://github.com/common-voice/cv-dataset/blob/main/datasets/scripted-speech/cv-corpus-27.0-2026-09-11.json. Tier: Established (counts); Speculative (hours estimate).

---

## 4. Part B: speakers worldwide

Primary source: Wikipedia's "List of languages by total number of speakers", whose main table is now **Ethnologue 2026** (retrieved by Wikipedia 2026-03-08), superseding the 2025 edition. https://en.wikipedia.org/wiki/List_of_languages_by_total_number_of_speakers and https://en.wikipedia.org/wiki/List_of_languages_by_number_of_native_speakers. Both lists only include languages above roughly 50 M speakers, so smaller languages come from each language's Wikipedia infobox, with the year shown.

| Language | Total (L1+L2) M | L1 M | Source / note | Tier |
|---|---|---|---|---|
| Arabic, macrolanguage | ≈481 (my sum: 411 L1 + 70 L2) | 411 (all varieties) | Wikipedia Arabic infobox (2020–2024) https://en.wikipedia.org/wiki/Arabic. Ethnologue 2026 does not list the macrolanguage; it lists **Standard Arabic 335 M (all L2, 0 L1)**, **Egyptian 118 total / 83 L1**, **Levantine 58 / 55**. **Figure used: 411 M L1 for "Arabic".** The varieties cannot be summed with MSA because they double-count. | Contested (macrolanguage) |
| Persian, macrolanguage | 127 | 91 | Wikipedia Persian infobox (Iranian + Dari + Tajik) https://en.wikipedia.org/wiki/Persian_language. Ethnologue 2026 **Iranian Persian 82 total / 65 L1**. **Figure used: Iranian Persian 82 / 65 for "Persian (Iran)"; 127 / 91 for the macrolanguage.** | Contested |
| Turkish | 94 | 86 | Ethnologue 2026 | Established |
| Russian | 210 | 133 | Ethnologue 2026 | Established |
| Ukrainian | 39 | 32 | Wikipedia infobox (2023) https://en.wikipedia.org/wiki/Ukrainian_language | Established, but post-2022 displacement makes it volatile |
| Polish | 43 | 40 | Wikipedia infobox (2021) https://en.wikipedia.org/wiki/Polish_language | Established |
| Dutch | 30 | 25 | Wikipedia infobox (2021; Eurobarometer, UofL) https://en.wikipedia.org/wiki/Dutch_language | Established |
| Greek | ≈13.5 (no L2 figure) | 13.5 | Wikipedia infobox (2015) https://en.wikipedia.org/wiki/Greek_language | Established (old figure) |
| Romanian | ≈22+ (no L2 figure) | 22 | Wikipedia infobox (2020) https://en.wikipedia.org/wiki/Romanian_language (includes Moldova) | Established |
| Czech | 12 | 9.8 | Wikipedia infobox (L1 2021, L2 2012) https://en.wikipedia.org/wiki/Czech_language | Established |
| Hindi | 611 | 347 | Ethnologue 2026. Second source: India Census 2011 counts **528.3 M** "Hindi" L1, which folds in Bhojpuri, Rajasthani and others; Ethnologue counts these separately. https://en.wikipedia.org/wiki/List_of_languages_by_number_of_native_speakers_in_India | Contested (definition) |
| Urdu | 246 | 78 | Ethnologue 2026. India alone, Census 2011: 50.8 M L1. | Established (Ethnologue); large L2 share from Pakistan |
| Bengali | 274 | 234 | Ethnologue 2026 (the native-speakers list gives 232). India Census 2011: 97.2 M (India only). | Established |
| Tamil | 86 | 79 | Ethnologue 2026. India Census 2011: 69.0 M (India only). | Established |
| Telugu | 96 | 83 | Ethnologue 2026. India Census 2011: 81.1 M. | Established |
| Marathi | 99 | 83 | Ethnologue 2026. India Census 2011: 83.0 M. | Established |
| Vietnamese | 97 | 86 | Ethnologue 2026 | Established |
| Indonesian | 255 | 78 | Ethnologue 2026. The L1 count is low because most Indonesians have a regional L1. | Established (Ethnologue); L1 Contested |
| Thai | 71 | 27 | Ethnologue 2026 (Central Thai only; Isan and others counted separately) | Contested (definition) |
| Filipino / Tagalog | 87 | 33 | Ethnologue 2026 | Established |
| Swahili | 95 (Ethnologue: 4 L1 + 91 L2). Wikipedia infobox: 5.3 L1 + 92 L2. | 4–5.3 | Wikipedia notes estimates "generally range from 40 million to 200 million" https://en.wikipedia.org/wiki/Swahili_language | **Contested** |
| Amharic | 78 | 39 | Ethnologue 2026 | Established |
| Hausa | 94 | 58 | Ethnologue 2026 | Established |
| Yoruba | 53 | 48 | Ethnologue 2026 | Established |
| Serbian | n/a (L1 only) | 8.2 | Wikipedia infobox citing Ethnologue 28th ed. (2025) https://en.wikipedia.org/wiki/Serbian_language. Serbo-Croatian as a whole (Serbian, Croatian, Bosnian, Montenegrin) is roughly 17–21 M; I did not verify this. | Serbian Established; Serbo-Croatian Speculative |
| Bulgarian | 7.9 | 6.8 | Wikipedia infobox (2019–2023) https://en.wikipedia.org/wiki/Bulgarian_language | Established |
| Hebrew (Modern) | 9 | 5 | Wikipedia infobox (2018 source) https://en.wikipedia.org/wiki/Hebrew_language | Established (dated) |

### Israel specifics

- **Population**, CBS year-end 2025: 10.178 M total. **Arabs 2,147,000 (21.1%)**. Jews and others 7.771 M (76.3%). Foreign nationals 0.26 M. Reported via JNS https://www.jns.org/israels-population-hits-10178000/ (CBS primary release not fetched). Tier: Established (consistent across several outlets).
- **Arabic as mother tongue**: the CBS 2011 Social Survey (age 20+) found **18%**, which was **about 1.44 M** adults. The newer CBS figure is about **20% of adults**, a later survey reported by Israel Hayom https://www.israelhayom.co.il/article/156509; its exact year is unverified. Sources: https://en.wikipedia.org/wiki/Languages_of_Israel and https://www.ynetnews.com/article/4335235.
  - Estimate: almost all 2.15 M Arab citizens speak Arabic as their L1. Druze and Bedouin speak Arabic too; Circassians are an exception. So **about 2.1 M Arabic L1 speakers in Israel**, about 21% of the population. This is my inference from the CBS population data plus the 18–20% survey figures. Tier: Speculative-to-Established (it agrees across both sources).
  - Arabic knowledge among Jews is low: 10% speak it fluently and 1% can read a book (Haaretz 2015 study, cited in the Wikipedia page above).
  - Arabic is also the language of about 5.5 M Palestinians in the West Bank and Gaza, which is not part of the Israel count. **Unknown**: I did not verify this figure this session.
- **Russian**: CBS 2011 found 15% mother tongue (**about 1.2 M**). The later survey found 13% of all Israelis (15% of Jews). Wikipedia says "up to 1.5 million Russian-speaking Israelis" (2017). Tier: Established (range 1.2–1.5 M).
- **Owner's claim** that Arabic is "spoken widely in Israel": **Established**. It is the L1 of about one in five Israelis, the largest L1 after Hebrew and ahead of Russian.

---

## 5. Gaps and next checks

- Licences that are Unknown: VietSuperSpeech, VietMed, RO-N3WS, VOA-Ukrainian (Zenodo), Russian Open STT, MGB-3, MediaSpeech (original source), and the DiaSet audio. Each needs a direct look at its card.
- VoxPopuli per-language test hours: the card does not give them. Check the paper (https://arxiv.org/abs/2101.00390).
- Babel packs for Turkish, Vietnamese, Amharic and Telugu: catalogue IDs not confirmed. LDC for-profit pricing not checked.
- Data Collective pages render through JavaScript, so per-dataset licence pages could not be fetched. The CC0 + ToS wording comes from search snippets and the Mozilla blog.
- Open question for the owner: does "internal scoring only, aggregate published" fall under "non-commercial research"? For GigaSpeech 2 the terms explicitly bind the for-profit employer. Treat as **not permitted** without written permission.
