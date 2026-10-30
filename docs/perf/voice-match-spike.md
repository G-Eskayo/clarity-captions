# In-ear translation that sounds like the speaker: spike (#247 part 1)

The owner's north star on #238: **the voice in your ear sounds like the person speaking**, with their intonation and
pace, at low latency. Part 1 asks whether Apple's own voices can get there cheaply: measure each speaker's pitch and
pace from the audio Seal already has, set `AVSpeechUtterance` voice, `pitchMultiplier` and `rate` to match, and
measure what that costs in lag. Part 2 (voice conversion) is research only, at the end.

No change to the app. The code is in the spike package `Packages/EarSpike`, which the app never references:

- `EarSpikeKit/SpeakerVoice.swift` (pure, 31 tests): `PitchTracker` (YIN), `SyllableRate` (loudness peaks),
  `TextSyllables` (syllables from caption text), `SpeakerProfile` (one per speaker, fed in the app's ~85 ms buffers),
  `VoiceMatch` (traits plus voice calibrations give voice, pitch and rate).
- `EarProbe/VoiceMatchProbe.swift` and `ear-spike voice-match`: the measurement below. It renders to buffers only, so
  **nothing plays**.

```sh
swift build -c release --package-path Packages/EarSpike
Packages/EarSpike/.build/release/ear-spike voice-match --out docs/perf/ear-translation
```

Raw numbers: [`ear-translation/voice-match-mac.json`](ear-translation/voice-match-mac.json).

## How it was measured

- **Machine:** MacBook Pro M1, macOS 27.0.1, 2026-10-30. **Load average was 250 to 500** during every run (other
  work on the machine), so the timings are an upper bound. The lag comparison alternates its arms line by line, so
  load lands on both.
- **Speakers:** four test speakers made from English voices set lower or higher, slower or quicker, so the right
  answer is known in direction (synthetic speech, not people in a room; see the limits). Each says two of the sample
  lines: that's what the app has heard by the time it speaks their first translation.
- **Target:** Spanish (`es-ES`), using the hand-written reference translations from #237 (the translation pair isn't
  installed on this Mac). The default is what the app does today: the best voice for the language (Mónica, compact),
  Apple's default pitch and rate.
- **Pitch:** median YIN pitch over voiced 10 ms frames. A laugh or a squeak doesn't move a median.
- **Pace:** syllables per second of speaking time, pauses over 0.3 s left out. Syllables are counted **from the
  caption text** (the app has it), and speaking time comes from the audio. Counting loudness peaks in the audio
  alone was too noisy: a voice's measured pace didn't even rise steadily with `rate` (Reed went 4.25, 4.03, 4.35, 4.71,
  4.29 syl/s over rates 0.4 to 0.6). From the text, every voice rises a steady 1.75 to 1.97 times over the same range.
  Pace is matched as **relative** pace: a speaker 20% slower than normal English gets a voice 20% slower than its
  normal Spanish, because Spanish carries more syllables for the same meaning.
- **Voice calibration (setup, once per voice):** each installed Spanish voice says three lines at rates 0.4 to 0.6
  and pitch multipliers 0.7 to 1.4. That gives how far each setting really moves it.

## Results

**Matched voices land within 0.4 semitones of each speaker's pitch, where today's voice is 1.4 to 9.1 semitones
off. Pace comes within 4 to 11%, where today's voice is 11 to 36% off. The lag added is about 0.5 ms.**

| Speaker (how made) | Heard as | Voice chosen | Pitch off: today → matched | Pace off: today → matched |
|---|---|---|---|---|
| 1: low, slow man (Daniel, rate 0.45, pitch 0.9) | 125 Hz, 3.80 syl/s | Eddy, pitch ×1.02, rate 0.42 | +5.8 → **+0.4** st | +36% → **+11%** |
| 2: high, quick woman (Samantha, 0.56, 1.1) | 189 Hz, 6.19 syl/s | Shelley, ×0.99, 0.563 | −1.4 → **−0.3** st | −17% → **+4%** |
| 3: like 2, slower (Sandy, 0.48, 1.0) | 296 Hz, 4.64 syl/s | Sandy, ×1.17, 0.502 | −9.1 → **+0.4** st | +11% → **+5%** |
| 4: quick man (Reed, 0.58, 1.0) | 113 Hz, 6.99 syl/s | Reed, ×1.04, 0.589 | +7.5 → **0.0** st | −26% → **+9%** |

Pitch off is the voice's measured pitch against the speaker's. Pace off is the voice's pace relative to its own
normal, against the speaker's pace relative to normal English (4.58 syl/s, the four voices at Apple's default).
Speaker 1 is pace-limited: they're slower than the lowest rate allowed (0.42) can reach.

**Four speakers, four different voices.** Today all four get Mónica, so two men and two women sound like the same
woman. Matched, the men get men's voices (Eddy 123 Hz, Reed 109 Hz) and the women get women's (Shelley 191 Hz,
Sandy 285 Hz).

### Lag

| Step | Cost | Note |
|---|---|---|
| Profiling the speaker as they talk | **2.0 to 2.6 ms per second of audio** (about 0.25% of one core) | runs on audio the app already captures, off the speaking path |
| Choosing voice, pitch and rate | **28 µs** for four speakers | at the moment a line is spoken |
| First sound, matched settings vs same voice at default | **+0.5 ms median** (mean +3.2, p95 +21, 40 lines) | noise at load ~290 |
| First sound, today's voice (Mónica compact) | 20.2 ms median (p95 44.8) | |
| First sound, matched voice | 9.3 ms median (p95 43.4) | the eloquence voices start faster than Mónica |

So **pitch and rate add no lag we can measure**, and the matched voices happened to start sooner than today's. The
#237 budget (about 0.95 s from end of speech to the voice, plus Bluetooth) is unchanged.

### How soon a speaker is matched

- **A profile is ready after 2.0 s of a speaker's audio** (the first 2-second piece with at least 1.5 s of speech).
  A new speaker's first phrase can come out in the default voice when it's spoken early (the 3-stable-words timing
  from #238 starts about 2 s before a line ends). From their second phrase on, it's theirs.
- **Two lines are close to enough.** Against a profile from all ten lines, two lines were within 0.6 semitones and 8%
  pace for three speakers. Speaker 1 was 2.4 semitones high on two lines (125 vs 109 Hz). Not enough to change the
  voice chosen; the profile keeps learning for 30 s of speech.

### Setup cost

Calibrating one voice took 2.9 to 6.1 s (27 s for the first, cold) on this loaded Mac: about a minute for Spanish's
nine voices. Apple's voices are the same files on every device, so the calibration can be **measured once by us and
shipped as a small table** (a few hundred bytes per voice). Only a voice missing from it would need measuring on the
device, in Settings, when the language is set up, never when the feature starts (owner's rule: nothing downloads or
prepares itself mid-feature).

## What the A/B is

[`ear-translation/voice-match-a-default.m4a`](ear-translation/voice-match-a-default.m4a) and
[`voice-match-b-matched.m4a`](ear-translation/voice-match-b-matched.m4a), 42 s each, about 250 KB, quiet
(about −26 dBFS). The same conversation in both: each of the four speakers says two English lines, each followed by
its Spanish translation. **A** is today's voice; **B** is matched. Listen for: can you tell who's talking from the
Spanish alone, and does it sound like the person, not just a different person?

## Limits

- **Synthetic speakers.** Apple voices standing in for people, fed digitally. Real voices vary more line to line, a
  room adds noise and echo, and the real profile depends on which audio the diarizer gives each speaker. Speaker
  labels that flip (#91, [`speaker-label-stability.md`](speaker-label-stability.md)) would flip the voice too, so a
  wired version should change a speaker's voice only on a settled label.
- **Pitch and pace, not timbre.** Matching moves the voice toward the speaker; it doesn't sound like them. Intonation
  within a sentence (rising questions, stress) isn't carried: `AVSpeechUtterance` has one pitch per utterance. A
  sentence could be split into phrases with their own pitch, but each split adds a voice start (8 to 61 ms, #237).
- **Pace from the caption text.** Syllables come from the text in Latin, Greek and Cyrillic scripts and from
  characters in Chinese, Japanese and Korean. Hebrew and Arabic are written without vowels, so `TextSyllables`
  returns nil and pace falls back to the noisier loudness peaks.
- **Premium and enhanced (neural) voices weren't measured.** The installed neural voice (Damon, en-US premium)
  was listed to a script but not to the command-line tool. Whether they follow `pitchMultiplier` is a device step.
  The compact (Mónica) and eloquence voices measured here all did: 6.1 to 10.9 semitones over ×0.7 to ×1.4.
- **One target language.** Spanish has nine voices with a wide spread (81 to 285 Hz). A language with one voice can
  only move pitch (±4 semitones allowed) and rate, and two speakers on one voice are kept at least 2 semitones apart.
- **Mac, not iPhone.** iOS has the same eloquence voices, but timings and voice lists are device steps.
- **Long renders came back cut.** Six and ten joined Spanish lines both rendered to the same 13.1 s, so everything is
  measured one line at a time. The app speaks one phrase per utterance, and #237 timed single lines, so neither is affected.

## Steps on the owner's iPhone (if wired)

1. **V1** The A/B above, through AirPods: pick A or B per turn, and say whether B sounds like the person.
2. **V2** Two people talking (a man and a woman, then two women), Speak it in my ear on: does each keep their own
   voice, and does a voice ever jump to the other person's?
3. **V3** The premium or enhanced Spanish voice downloaded: does it follow the pitch at all?

## Part 2: on-device voice conversion and cloning (research only)

Part 1 can only pick the nearest Apple voice and move it. Sounding like the person means changing the timbre:
**voice conversion** (turn Apple's spoken translation into the speaker's voice) or **cloning TTS** (synthesise
straight in their voice from a few seconds of them). What's out there, as of 2026-10-30:

| Option | What it is | Size and speed | Licence for a paid app | Fit |
|---|---|---|---|---|
| **StreamVC** (Google, ICASSP 2024, [arXiv 2401.03078](https://arxiv.org/abs/2401.03078)) | Streaming any-to-any conversion, keeps the source's pitch contour (whitened f0) | **70.8 ms latency on a Pixel 7** | Paper only, no code or weights released | The right shape (streaming, phone-sized, timbre only); we'd have to build and train it |
| **LLVC** (Koe AI, [arXiv 2311.00873](https://arxiv.org/abs/2311.00873), [code](https://github.com/KoeAI/LLVC)) | Low-latency conversion on CPU | **Under 20 ms** at 16 kHz, 2.8× faster than real time on a consumer CPU | Repo is MIT; weights' terms not stated | **One fixed target voice**, so it can't become "this speaker" |
| **OpenVoice V2** (MyShell, [repo](https://github.com/myshell-ai/OpenVoice)) | Zero-shot tone-colour converter applied after a TTS voice; native en, es, fr, zh, ja, ko | Not streaming; a desktop/GPU model | **MIT, "free for commercial use"** (README) | The closest drop-in for converting Apple's voice to the speaker's tone colour; needs a Core ML port and a size and heat check |
| **Seed-VC** ([repo](https://github.com/Plachtaa/seed-vc)) | Zero-shot conversion, real-time mode | About 300 ms algorithm delay, GPU recommended | Unclear: a mirror says GPL-3.0, the main repo doesn't say | Too slow, and GPL would rule it out of a closed App Store app |
| **Apple Personal Voice** ([AVSpeechSynthesizer docs](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/requestpersonalvoiceauthorization(completionhandler:))) | The device owner records their own voice; apps can ask to use it | On-device, Apple's | Free, but needs the user's permission and "Allow Apps to Request to Use" on | **Only the owner's own voice.** It can't be anyone else's, so it doesn't answer this ticket (it could voice the owner's replies in a later two-way mode) |

**Consent and misuse.** Cloning the person in front of you is the hard part, not the model. They never agreed to it,
and a model that can clone anyone from a few seconds is a tool for impersonation and fraud. Consumer Reports found
popular cloning apps did little to check consent
([report](https://www.consumerreports.org/electronics/identity-theft/voice-cloning-apps-let-criminals-easily-steal-your-voice-a6024784872)).
Any version here should: keep the clone in memory for the session only, never save, export or share it, never let
it say anything but the live translation of what that person just said, and be off by default with a plain
explanation. The App Store guidelines I could check don't name voice cloning; the privacy rules (5.1) and
"objectionable or harmful" content would be how a reviewer judges it. That needs reading against the current
guidelines before any build.

**Size and heat.** Seal's models are kept small for the install-size budget
([`install-size-2026-10-29.md`](install-size-2026-10-29.md)). A conversion model running the whole time the voice
speaks, on top of captions, diarization and translation, is a battery and heat cost no one has measured on an
iPhone. StreamVC's 70.8 ms on a Pixel 7 is the only phone number found.

**Where it leaves us:** no option is ready to ship. If the owner wants timbre later, OpenVoice V2's tone-colour
converter is the one to port and measure first: licence OK, one of its native languages is Spanish. It would start
as a separate spike with the consent rules above, after part 1 is wired and heard on a real phone.
