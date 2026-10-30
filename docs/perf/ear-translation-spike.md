# Live Translation in your ear: spike (#233)

What can be measured without a microphone: on the M4 Mac mini (macOS 26.5.1) and the iPhone 17 Pro simulator
(iOS 26.5). Steps that need a real mic and real headphones are at the end, for the MacBook or the owner's iPhone and
iPad. Raw numbers are in [`ear-translation/`](ear-translation/); the tool is `Packages/EarSpike` (never referenced by
the app). Run any measurement again with `swift run --package-path Packages/EarSpike ear-spike <command> --out DIR`.

## The answer in one paragraph

On the device, **a finished line can be in your ear about 1 second after the person stops talking**, plus whatever
the Bluetooth headphones add. Almost all of that second is the caption engine deciding the line is finished (median
0.86 s). Translating takes about 0.05 s and the voice starts in about 0.02 s once it's warm. The voice must be
**warmed up when the feature is turned on**, because the first sentence in a new voice can take 0.1 to 10 s. Every
translation language on this Mac and on the iPhone simulator has an on-device voice. Serbian, Persian, Urdu and the
Baltic languages have no voice on iOS at all. The spoken translation does come back as caption nonsense if the mic
hears it. A text guard catches most of it (about 7 in 10 in simulation), so it's a backup. The real fix is to **keep
the phone's mic for listening and play only into the headphones** (no call profile), which ADR 0021 already does.

## Speech to voice lag

| Step | Median | p95 | Where measured |
|---|---|---|---|
| End of speech → finished caption line | **859 ms** | 1157 ms | Mac, EdAcc real speech fed in real time, 87 lines ([`finish-lag-mac.json`](ear-translation/finish-lag-mac.json)) |
| Translate one caption line (Apple Translation) | 51–70 ms | 69–110 ms | Mac, 19 languages, #159 ([translation-languages-results.md](translation-languages-results.md)); **not re-measured here**, see below |
| Finished translation → first audible sample (warm voice) | 10–61 ms Mac, 8–41 ms simulator | up to 140 ms Mac, 102 ms simulator | 10 languages × 10 lines ([`lag-mac.json`](ear-translation/lag-mac.json), [`simulator-iphone.json`](ear-translation/simulator-iphone.json)) |
| First sentence in a voice (cold) | 74–389 ms Mac, 69–207 ms simulator | the first voice of a run: 225 ms Mac, 981 ms simulator; **10.1 s** and 1.5 s in two earlier simulator runs right after boot (seen in the logs, not kept in the file) | same files |
| Output path | 1.25 ms Mac speakers, 0.1 ms simulator | | `presentationLatency` / `outputLatency`; Bluetooth headphones add their own, **device only** |

**Total for finished lines: about 0.95 s median, 1.3 s p95, before Bluetooth.**

- Translation timings couldn't run here: every pair now reads "supported", not "installed", on this Mac (E22 says
  they were installed on 2026-10-26; the assets look cleared to free disk space), and installing one needs Apple's
  download sheet, which needs a person. The simulator reports every pair **unsupported** (`TranslationError
  unsupportedLanguagePairing`): **the simulator cannot translate at all.**
- The cold start is why the voice has to be warmed up when the feature is turned on, not on the first line.

### Speaking sooner than the finished line

On the same stream, the first words of a line are usually right, and stay right, well before the line is finished
([`PhraseTiming`](../../Packages/EarSpike/Sources/EarSpikeKit/PhraseTiming.swift)):

| Words held still | Lines where it happens | Median head start before the finished line |
|---|---|---|
| First 3 words | 54 of 87 | **2.0 s** |
| First 5 words | 42 of 87 | **2.8 s** |

That's a big win in theory, but translating a piece of a sentence often reorders badly (German verbs at the end,
Japanese word order), and a spoken word can't be taken back. This spike **did not measure** translation quality on
partial lines. It is offered as a Decision (finished lines only, or the first phrase sooner) with finished lines as
the safe default.

## Which translation languages have a voice

The Mac (macOS 26) and the iPhone simulator (iOS 26.5) both list **38 translation languages**, and **all 38 have an
on-device voice** ([`voices-mac.json`](ear-translation/voices-mac.json), `simulator-iphone.json` → `voices`).
Translation's own list on this OS has **no Hebrew**; the owner found 47 languages, Hebrew included, on macOS 27.

The iPhone simulator has 68 voices in **49 locales**:
`ar-001 bg-BG bn-IN ca-ES cs-CZ da-DK de-DE el-GR en-AU en-GB en-IE en-IN en-US en-ZA es-ES es-MX fi-FI fr-CA fr-FR
he-IL hi-IN hr-HR hu-HU id-ID it-IT ja-JP kn-IN ko-KR ms-MY nb-NO nl-BE nl-NL pl-PL pt-BR pt-PT ro-RO ru-RU sk-SK sl-SI
sv-SE ta-IN te-IN th-TH tr-TR uk-UA vi-VN yue-HK zh-CN zh-TW`.

- **Hebrew has a voice** (`he-IL` Carmit), on iOS and the Mac.
- **No voice on iOS:** Serbian, and anything not in that list (for example Persian, Urdu, Filipino, Swahili,
  Lithuanian, Latvian, Estonian). These are **captions only**. The app should say so on that language's row, not
  pretend.
- The simulator ships only "super-compact" voices. Real iPhones download better ("enhanced"/"premium") voices in
  Settings, so the voice quality and the coverage table must be **re-run on the owner's iPhone** (step D4).
- Still open: the table for the 47 languages of macOS 27 / iOS 27. Run `ear-spike voices` on the MacBook (step M1).

## Echo: the translation captioned back

The caption engine listens in the other person's language, so it doesn't hear the app's Spanish voice as Spanish: it
hears **English-sounding nonsense** ("¿Nos trae la cuenta?" → "No, strike, la quanta"; Japanese came back as "Okay,
okay, okay, okay."). Fed straight into the engine (digital, the worst case), **every one of 60 spoken lines produced
a caption** ([`echo-digital-mac.json`](ear-translation/echo-digital-mac.json)). Shown, those would be false captions,
and translated, they would be spoken again: a loop.

`EchoGuard` drops a finished caption that overlaps the time the app was speaking (plus a 0.8 s room tail) **and**
looks like what the app said. Matching only the translated words caught 1 to 4 lines in 10. Two things fixed most of it:

1. **Fingerprint:** before playing a line, the app runs its caption engine on the audio it's about to play (it
   already has the buffers) and remembers what the engine heard.
2. **Letters, not just words:** the nonsense changes its word breaks between the clean audio and the way back
   ("yudadamuto" → "yugada mucho"), so letter trigrams back up whole words.

Simulated way back (8 kHz band, and 8 kHz + noise at 10 dB) across Spanish, French, German, Italian, Hebrew and Japanese,
120 echoes ([`echo-fingerprint-mac.json`](ear-translation/echo-fingerprint-mac.json)):

| Guard | Echoes dropped | Real lines wrongly dropped |
|---|---|---|
| Translated text only (words + letters) | 49 of 120 | |
| With the fingerprint | **83 of 120** | **1 of 600** |

The letter threshold (0.35) was tuned on this same set, so these numbers are **optimistic**. The guard is a
backup. The main defence is physical:

- **Headphones on, the phone's mic listening** (ADR 0021): the voice is in your ears, not in the room. What
  leaks from open earbuds at full volume has to be measured (step D2).
- **Apple's voice processing** (echo cancellation on the input) knows what the app is playing and removes it.
  The Mini has no mic to test it (step D3).
- If headphones disconnect, the voice must **not** carry on through the phone's speaker (a Decision in the mock-up).

## Headset mic vs phone mic (what can be said without a mic)

A Bluetooth headset's mic switches the headphones to the call profile (HFP): 16 kHz (mSBC) or 8 kHz (CVSD) audio,
and the music-quality output (A2DP) drops while it's on.

| Real conversational English (EdAcc, 80 clips, 3–15 s) | WER |
|---|---|
| 16 kHz, the band an mSBC headset mic carries | 20.5% |
| Narrowed to 8 kHz (CVSD, older headsets) | 21.4% (worse on 20 of 80 clips) |

([`headset-real-mac.json`](ear-translation/headset-real-mac.json); the absolute WER is high because EdAcc's
references keep "um" and "uh"; only the gap matters.) **The band itself costs Apple's engine little.** What it
doesn't show, and only a device can: the Bluetooth codec's loss, the headset's own noise suppression, a mic by your
cheek hearing **you** louder than the other person, and the call profile lowering the voice's quality in your ear.

**Recommendation:** keep the phone's mic for listening (ADR 0021), play into the headphones over A2DP, and never
switch to the headset's mic. `.playAndRecord` with `.allowBluetoothA2DP` and **not** `.allowBluetoothHFP`, built-in mic
as the preferred input. Apple developer forum thread 741513 reports exactly this setup working (built-in mic in,
AirPods out), and 784318 reports the route saying "built-in" while the samples came from the AirPods. So the device
test must check the samples, not the route (step D1). This also sidesteps the call-profile quality drop. The other
option, the headset mic for loud rooms, is a later choice if D1 shows the phone mic fails.

## Apple's own AirPods Live Translation

Apple's newsroom (Nov 2025) lists English, French, German, Portuguese, Spanish, Italian, Chinese (Simplified and
Traditional), Japanese and Korean, on AirPods Pro 2/3 and AirPods 4 with ANC, with an Apple Intelligence iPhone.
Seal's edge: **any headphones, any iPhone that runs Seal, captions on screen at the same time, and every language
with a voice** (Hebrew, Russian, Arabic, Hindi, Turkish, ...). Possible conflict: if both are on, two voices speak.
The device test checks what happens when Apple's is also on (step D5). Seal can't turn it off.

## App Review (docs/app-review-risks.md, Guideline 2.5.4)

- Speaking out loud is **playback**, which makes the `audio` background mode easier to justify than captions alone.
  The feature still has to start in the foreground and **stop when the app goes to the background** unless the
  owner chooses otherwise. Background stays on hold as in the risks doc. That keeps risk 3 at "None".
- `.playAndRecord` + `.duckOthers`: it lowers other audio while it speaks. Say so in the review notes.

## What the simulator cannot show

- **Translation:** every pair is unsupported on the simulator.
- **Any microphone path:** there's no headset, no Bluetooth route, no HFP, no echo cancellation, and the simulator's
  "built-in mic" is the Mac's.
- **Bluetooth output latency** and quality, AirPods vs other headphones.
- **Real voice quality:** only super-compact voices exist; iPhones download better ones.
- **Phone-speed numbers:** all timings here are Mac (M4) timings; the simulator runs on the Mac's CPU.

## Steps that need a real mic (MacBook, or the owner's devices)

On the **MacBook** (has a mic, macOS 27):

- **M1.** `swift run --package-path Packages/EarSpike ear-spike voices --out docs/perf/ear-translation --name voices-macbook.json`: the voice table for all 47 languages (Hebrew included).
- **M2.** `ear-spike lag --speak`: translate timings with installed pairs (install Spanish, French, German, Hebrew and
  Japanese first in System Settings → General → Language & Region → Translation Languages).
- **M3.** `ear-spike acoustic --target es --keep`: the speaker-to-mic echo, voice processing off and on. Then
  `ear-spike headset --room`: the room-mic accuracy.

On the **owner's iPhone** (and iPad, Duo), with a debug build of the spike once the mock-up is approved:

- **D1. Phone mic vs headset mic.** AirPods, then a non-Apple Bluetooth headset, then wired/USB-C earbuds. For each:
  caption the same 2-minute reading (someone across the table) with the phone's mic and again with the headset's mic.
  Note WER and whether the voice in your ear gets worse when the headset's mic is on. Check the **samples**, not the
  route name.
- **D2. Leak.** Phone mic listening, AirPods playing the translation at full volume, nobody talking: does anything get
  captioned? Repeat with open earbuds and with the phone on the table vs in the hand.
- **D3. Voice processing.** D2 with the phone's speaker instead of headphones, voice processing on and off.
- **D4. Voices.** The voice table and cold-start time on a real iPhone, with and without an enhanced voice downloaded.
- **D5. Apple's Live Translation** on AirPods Pro at the same time: do two voices speak?
- **D6. Live lag.** Stopwatch from the end of a spoken sentence to the first sound in the ear, AirPods vs another
  headset (Bluetooth output delay), 10 sentences each.
