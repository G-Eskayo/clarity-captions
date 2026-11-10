# Whole-system replay: 1.0 (5) vs 1.1.0 (10) on the same audio (#273)

Run 2026-11-09 on the M4 Mac mini (macOS 26.5, release builds), scored on the 2012 Mac mini from the committed
scorer (`cd36987`). Method, builds and limits: [whole-system-replay-design.md](whole-system-replay-design.md).
Raw scores: [whole-system-replay-results-2026-11-09.json](whole-system-replay-results-2026-11-09.json).

## What it says

1. **On clean recorded conversation, build 10 is not worse than 1.0.** Through the microphone's own path (arm D),
   build 10 scores 18.3% against 1.0's 18.3% (paired difference +0.1 points, 95% CI −1.2 to +1.6). Through the
   engine's replay path (arm B), 17.2% (−1.1, CI −2.3 to +0.7). The "very inaccurate" demo does not reproduce here.
2. **Nothing build 10 changed outside the engine moved accuracy.** Build 10 forced onto Apple's engine (arm C) gives
   1.0's text word for word in all 40 conversations.
3. **The live path throws away most of Parakeet's lead.** Alone on the same clips (#145), Parakeet is 3.9 points
   better than 1.0 (14.4% vs 18.3%, CI −5.0 to −2.5). Through the app, on the sessions that stayed on Parakeet, it keeps 1.7 of
   those points on the replay path (CI −2.7 to −0.5 against 1.0) and about none on the mic path (−0.3, CI −1.6 to
   +1.4). On those sessions the mic path is 3.4 points worse than
   Parakeet alone (CI +2.5 to +4.4), the replay path 2.6 (CI +1.4 to +4.0). Mic path minus replay path is +1.2
   (CI −0.1 to +2.5): probably real, not yet shown at this sample size.
4. **Build 10 leaves Parakeet for Apple mid-session on any memory-pressure warning**, and stays there; nothing on
   screen says so. 8 of 40 sessions in B, 4 of 40 in D, every one `memoryWarning`
   (`ParakeetBackend`: a system-wide `DispatchSource` memory-pressure source, `.warning` included). On this Mac
   the rate is an artefact: swap was 8.8 of 9.2 GB used, with other jobs (a simulator, a model conversion) running.
   The behaviour is the app's own, and a phone running Live Translation or voice match is a likely place for it.
   The switched sessions did not lose measurably more text than 1.0 (B: +1.4, CI −2.0 to +5.8; D: +2.0, CI −1.7
   to +10.3; 8 and 4 conversations, too few to say more).

So the Mac rules out, for clean audio (and, below, for room noise): build 10's code outside the engine, and a Parakeet that is plainly worse
than Apple on the live path. It leaves the things only the phone and the room have (see the design doc's device-run
list): the phone's mic and audio session, translation into the ear, voice match, real memory pressure.

## What the live path gets wrong (one conversation, a lead, not a result)

`test-EDACC-C29_P2`, arm B against Parakeet alone: lines break mid-sentence ("How do you see" / "mean I think the
network is bad."), words at those breaks are misheard ("use that" → "see mean", "bygones" → "by guns"), and one
"yes" came out as "olha jestli" (Portuguese and Czech): the multilingual model drifting language on a short chunk.
Over the 32 conversations that stayed on Parakeet, the live path adds 47 substitutions, 17 deletions and 39
insertions to Parakeet-alone's errors (3,888 reference words). Some "insertions" are words the live path caught and
the file run missed, so this is not all loss.

## Scores

40 conversations, 58 speakers, 37.0 minutes of audio. WER pooled over conversations; 95% CIs resample conversations (1,000 resamples).

| Arm | WER | 95% CI | Words | Left Parakeet | Fallbacks | Word lag p50 / p95 | Finished-line lag p50 / p95 |
|---|---|---|---|---|---|---|---|
| A 1.0 Apple | 18.3% | 15.7% to 20.9% | 4922 | 0 | none | -0.07 s / -0.04 s | n/a / n/a |
| B 10 Parakeet | 17.2% | 14.6% to 20.0% | 4922 | 8 | memoryWarning x8 | 0.22 s / 0.89 s | n/a / n/a |
| C 10 Apple | 18.3% | 15.7% to 20.9% | 4922 | 0 | none | -0.07 s / -0.06 s | n/a / n/a |
| D 10 Parakeet source | 18.3% | 15.9% to 21.1% | 4922 | 4 | memoryWarning x4 | 0.28 s / 0.96 s | 1.01 s / 1.99 s |
| engine-only Parakeet (ultra-pal6, #145) | 14.4% | 12.3% to 16.7% | 4922 | 0 | none | n/a / n/a | n/a / n/a |
| engine-only Apple (SpeechTranscriber en-US, #145) | 18.4% | 15.9% to 21.0% | 4922 | 0 | none | n/a / n/a | n/a / n/a |

Paired differences (same conversations; a CI that excludes 0 is a real difference):

| Difference | WER points | 95% CI |
|---|---|---|
| B 10 Parakeet minus A 1.0 Apple | -1.1 | -2.3 to +0.7 |
| C 10 Apple minus A 1.0 Apple | +0.0 | +0.0 to +0.0 |
| D 10 Parakeet source minus A 1.0 Apple | +0.1 | -1.2 to +1.6 |
| engine-only Parakeet (ultra-pal6, #145) minus A 1.0 Apple | -3.9 | -5.0 to -2.5 |
| engine-only Apple (SpeechTranscriber en-US, #145) minus A 1.0 Apple | +0.2 | -0.5 to +0.9 |
| C 10 Apple minus B 10 Parakeet | +1.1 | -0.7 to +2.3 |
| D 10 Parakeet source minus B 10 Parakeet | +1.2 | -0.1 to +2.5 |
| engine-only Parakeet (ultra-pal6, #145) minus B 10 Parakeet | -2.8 | -4.0 to -1.6 |
| engine-only Apple (SpeechTranscriber en-US, #145) minus B 10 Parakeet | +1.3 | -0.2 to +2.4 |
| D 10 Parakeet source minus C 10 Apple | +0.1 | -1.2 to +1.6 |
| engine-only Parakeet (ultra-pal6, #145) minus C 10 Apple | -3.9 | -5.0 to -2.5 |
| engine-only Apple (SpeechTranscriber en-US, #145) minus C 10 Apple | +0.2 | -0.5 to +0.9 |
| engine-only Parakeet (ultra-pal6, #145) minus D 10 Parakeet source | -4.0 | -5.1 to -3.1 |
| engine-only Apple (SpeechTranscriber en-US, #145) minus D 10 Parakeet source | +0.1 | -1.2 to +1.2 |
| engine-only Apple (SpeechTranscriber en-US, #145) minus engine-only Parakeet (ultra-pal6, #145) | +4.1 | +2.9 to +5.0 |

Arms that left Parakeet mid-session, split by their own engine record (WER of each part, paired with the reference on the same conversations):

| Arm | Part | Conversations | Arm WER | Reference | Reference WER | Arm minus reference | 95% CI |
|---|---|---|---|---|---|---|---|
| B 10 Parakeet | stayed on Parakeet | 32 | 17.1% | A 1.0 Apple | 18.9% | -1.7 | -2.7 to -0.5 |
| B 10 Parakeet | left Parakeet | 8 | 17.4% | A 1.0 Apple | 16.1% | +1.4 | -2.0 to +5.8 |
| B 10 Parakeet | stayed on Parakeet | 32 | 17.1% | engine-only Parakeet (ultra-pal6, #145) | 14.5% | +2.6 | +1.4 to +4.0 |
| B 10 Parakeet | left Parakeet | 8 | 17.4% | engine-only Parakeet (ultra-pal6, #145) | 14.0% | +3.4 | +1.0 to +6.4 |
| B 10 Parakeet | stayed on Parakeet | 32 | 17.1% | engine-only Apple (SpeechTranscriber en-US, #145) | 18.8% | -1.7 | -2.8 to -0.2 |
| B 10 Parakeet | left Parakeet | 8 | 17.4% | engine-only Apple (SpeechTranscriber en-US, #145) | 17.1% | +0.3 | -2.6 to +4.1 |
| D 10 Parakeet source | stayed on Parakeet | 36 | 17.9% | A 1.0 Apple | 18.2% | -0.3 | -1.6 to +1.4 |
| D 10 Parakeet source | left Parakeet | 4 | 21.1% | A 1.0 Apple | 19.0% | +2.0 | -1.7 to +10.3 |
| D 10 Parakeet source | stayed on Parakeet | 36 | 17.9% | engine-only Parakeet (ultra-pal6, #145) | 14.5% | +3.4 | +2.5 to +4.4 |
| D 10 Parakeet source | left Parakeet | 4 | 21.1% | engine-only Parakeet (ultra-pal6, #145) | 13.7% | +7.3 | +6.3 to +10.1 |
| D 10 Parakeet source | stayed on Parakeet | 36 | 17.9% | engine-only Apple (SpeechTranscriber en-US, #145) | 18.3% | -0.4 | -1.7 to +1.1 |
| D 10 Parakeet source | left Parakeet | 4 | 21.1% | engine-only Apple (SpeechTranscriber en-US, #145) | 19.5% | +1.6 | -1.3 to +7.2 |

Lag: the engine's own word lag (ADR 0015). Apple's is negative on the replay path because each buffer is handed over
at its start (design doc, Scores); compare replay arms with each other. Finished-line lag (mic path only): p50
1.01 s, p95 1.99 s.

## The owner's session data (2026-11-10): the caption language, not the engine

The owner shared the demo phone's beta report and the saved transcript of the bad conversation (kept private;
summarised here). The report says **1.1.0 (9)**, TestFlight, iPhone18,1, iOS 27.2; the phone's language and region
are English (United States). Quiet jazz in the background, two people taking turns.

- **All six sessions (Oct 30 to Nov 6) ran Apple's engine with `engineFallback = "locale"`.** Parakeet never ran,
  and no session fell back for memory. In build 9, `locale` means the caption language's language code wasn't
  English (`EngineFallbackPolicy.engine`), so Apple's engine was told to hear another language.
- **The report's build is the build when it was sent** (`CFBundleVersion` at send time); sessions don't record their
  own. The phone was on build 9 on Nov 10, so the bad Nov 6 session was very likely build 9, not build 10.
- **The transcript has the shape of English heard as another language**: English-like fragments with consonants and
  whole words missing, under half the words recognisable, rated 1 of 10.

**Reproduced on the Mac** (8 validation conversations, 4.2 min, mic path; `scripts/system-replay/run-locale.sh`;
[whole-system-replay-locale-2026-11-10.json](whole-system-replay-locale-2026-11-10.json)): English speech with the
caption language set to another language.

| Caption language | Build 9 (Apple, `locale`) | Build 10 (Parakeet) |
|---|---|---|
| en-US | 18.2% (Apple forced) / 20.1% (Parakeet) | 18.1% |
| es-ES | 56.2% | 19.4% |
| pt-BR | 71.5% | 20.3% |
| fr-FR | 76.2% | 18.6% |
| de-DE | 67.2% | 18.1% |
| it-IT | 52.0% | 19.7% |

A wrong caption language costs build 9 **34 to 58 points** (paired against English, every CI excludes 0) and gives
the same kind of text as the phone's: English-shaped words with letters missing ("somime", "mywe"). Build 10 is
unaffected (0.0 to +2.2 points), because since #234 it sends every language Parakeet covers to Parakeet, and Parakeet
takes no language setting: it hears the language. Dutch and Czech couldn't be tested (Apple has no transcription
model for them on this Mac). The jazz was not mixed in; the pattern matches without it.

**How a non-English caption language gets there on an en-US phone (build 9 code):** following the device would give
en-US, so it was **saved**. Only two things save it: a pick in Settings › Caption language
(`CaptionLanguageCenter.choose`) and first run's language question (`FirstRunView.chooseLanguage`, asked only when the
device's language doesn't settle it). It is kept in `UserDefaults` (`captionLanguage`), which survives every TestFlight
and App Store update, so a pick made while trying another language in any build since #37 stays in force until it is
changed or the app is deleted. Nothing on the caption screen shows it. A second path: face to face with one half
picked runs one-way captions in that half's language (#208, `ContentView` `.one(_, locale)`), in memory only. The
report records neither the caption language nor face to face, so it can't say which; Seal › Settings › Caption
language on the phone can.

**Also found:** the Oct 31 session reports 13,558.4 minutes with no ending. That is exactly the time from its start
to the report being sent: a captioning segment that never got its stop (the app closed while captioning and the
conversation was never restored) keeps counting until the report is made (`ConversationRecorder.entry(now:)`). A
reporting bug, not a 9-day session.

## Room noise (2026-11-10)

The same 40 conversations mixed into real rooms (DEMAND: restaurant, cafeteria, living room, car; one room per
conversation by a hash of its id) at 10 dB and 0 dB SNR, the design fixed before the run (design doc, Noise). Arms
A, C, D, each session started only at normal memory pressure. Scores in
[whole-system-replay-noise-10db-2026-11-10.json](whole-system-replay-noise-10db-2026-11-10.json) and
[…-0db-…](whole-system-replay-noise-0db-2026-11-10.json); the clean A and D runs are scored alongside, so every
difference is paired on the same conversations.

1. **Noise doesn't make build 10 worse than 1.0; it makes 1.0 worse faster.** Build 10 (mic path) minus 1.0:
   −1.6 points at 10 dB (CI −3.3 to +0.2), **−3.8 at 0 dB (CI −5.5 to −1.9)**. The room-noise explanation for the
   demo, Parakeet's live path falling apart in a room where Apple's holds, is ruled out on this data.
2. **Build 10 on Apple's engine gives 1.0's text word for word** at both levels (40 of 40 each).
3. **Both are poor in a loud room.** 0 dB costs 1.0 21.1 points and build 10 17.3. By room at 0 dB: restaurant
   76.8% (1.0) vs 68.6% (10), cafeteria 49.6% vs 48.2%, living room 32.6% vs 28.5%, car 16.3% vs 14.3% (8, 8, 16
   and 8 conversations; read as direction, not as per-room results).
4. **No session left Parakeet** at either level: with the memory gate on, the clean run's `memoryWarning` switches
   did not recur, which supports reading them as this Mac's swap.
5. **Build 10's finished lines come later in noise:** p95 1.99 s clean, 2.76 s at 10 dB, 4.32 s at 0 dB (p50 1.01,
   1.03, 1.21 s). Apple's line lag isn't measured on the replay path, so this has no 1.0 comparison yet.

### 10 dB

| Arm | WER | 95% CI | Words | Left Parakeet | Fallbacks | Word lag p50 / p95 | Finished-line lag p50 / p95 |
|---|---|---|---|---|---|---|---|
| A 1.0 Apple, clean | 18.3% | 15.7% to 20.9% | 4922 | 0 | none | -0.07 s / -0.04 s | n/a / n/a |
| D 10 Parakeet mic path, clean | 18.3% | 15.9% to 21.1% | 4922 | 4 | memoryWarning x4 | 0.28 s / 0.96 s | 1.01 s / 1.99 s |
| A 1.0 Apple, 10 dB | 23.5% | 19.4% to 27.8% | 4922 | 0 | none | -0.06 s / -0.01 s | n/a / n/a |
| C 10 Apple, 10 dB | 23.5% | 19.4% to 27.8% | 4922 | 0 | none | -0.07 s / -0.01 s | n/a / n/a |
| D 10 Parakeet mic path, 10 dB | 21.9% | 18.4% to 25.3% | 4922 | 0 | none | 0.32 s / 0.98 s | 1.03 s / 2.76 s |
| Difference | WER points | 95% CI |
|---|---|---|
| D 10 Parakeet mic path, clean minus A 1.0 Apple, clean | +0.1 | -1.2 to +1.6 |
| A 1.0 Apple, 10 dB minus A 1.0 Apple, clean | +5.3 | +2.8 to +7.6 |
| C 10 Apple, 10 dB minus A 1.0 Apple, clean | +5.3 | +2.8 to +7.6 |
| D 10 Parakeet mic path, 10 dB minus A 1.0 Apple, clean | +3.6 | +1.5 to +6.0 |
| A 1.0 Apple, 10 dB minus D 10 Parakeet mic path, clean | +5.2 | +2.2 to +8.2 |
| C 10 Apple, 10 dB minus D 10 Parakeet mic path, clean | +5.2 | +2.2 to +8.2 |
| D 10 Parakeet mic path, 10 dB minus D 10 Parakeet mic path, clean | +3.6 | +1.2 to +5.7 |
| C 10 Apple, 10 dB minus A 1.0 Apple, 10 dB | +0.0 | +0.0 to +0.0 |
| D 10 Parakeet mic path, 10 dB minus A 1.0 Apple, 10 dB | -1.6 | -3.3 to +0.2 |
| D 10 Parakeet mic path, 10 dB minus C 10 Apple, 10 dB | -1.6 | -3.3 to +0.2 |
### 0 dB

| Arm | WER | 95% CI | Words | Left Parakeet | Fallbacks | Word lag p50 / p95 | Finished-line lag p50 / p95 |
|---|---|---|---|---|---|---|---|
| A 1.0 Apple, clean | 18.3% | 15.7% to 20.9% | 4922 | 0 | none | -0.07 s / -0.04 s | n/a / n/a |
| D 10 Parakeet mic path, clean | 18.3% | 15.9% to 21.1% | 4922 | 4 | memoryWarning x4 | 0.28 s / 0.96 s | 1.01 s / 1.99 s |
| A 1.0 Apple, 0 dB | 39.4% | 30.1% to 50.7% | 4922 | 0 | none | -0.06 s / -0.01 s | n/a / n/a |
| C 10 Apple, 0 dB | 39.4% | 30.1% to 50.7% | 4922 | 0 | none | -0.06 s / -0.05 s | n/a / n/a |
| D 10 Parakeet mic path, 0 dB | 35.6% | 26.4% to 45.4% | 4922 | 0 | none | 0.35 s / 1.09 s | 1.21 s / 4.32 s |
| Difference | WER points | 95% CI |
|---|---|---|
| D 10 Parakeet mic path, clean minus A 1.0 Apple, clean | +0.1 | -1.2 to +1.6 |
| A 1.0 Apple, 0 dB minus A 1.0 Apple, clean | +21.1 | +13.0 to +30.4 |
| C 10 Apple, 0 dB minus A 1.0 Apple, clean | +21.1 | +13.0 to +30.4 |
| D 10 Parakeet mic path, 0 dB minus A 1.0 Apple, clean | +17.4 | +9.6 to +25.5 |
| A 1.0 Apple, 0 dB minus D 10 Parakeet mic path, clean | +21.1 | +12.5 to +31.2 |
| C 10 Apple, 0 dB minus D 10 Parakeet mic path, clean | +21.1 | +12.5 to +31.2 |
| D 10 Parakeet mic path, 0 dB minus D 10 Parakeet mic path, clean | +17.3 | +9.2 to +26.2 |
| C 10 Apple, 0 dB minus A 1.0 Apple, 0 dB | +0.0 | +0.0 to +0.0 |
| D 10 Parakeet mic path, 0 dB minus A 1.0 Apple, 0 dB | -3.8 | -5.5 to -1.9 |
| D 10 Parakeet mic path, 0 dB minus C 10 Apple, 0 dB | -3.8 | -5.5 to -1.9 |
## Next

- **Noise: done** (above). It doesn't explain the demo.
- **The device run** (design doc): build 10 on the demo phone, with translation, ear and voice match as the owner
  had them, the beta report's `engine` and `engineFallback` logged.
- **The owner's session data: done** (above). The demo was the caption language.
- **Separate tickets worth opening:** a memory warning switches the whole session to Apple silently; the live path's
  chunk boundaries cost Parakeet 2.6–3.4 points; FluidAudio is not pinned for the app (design doc, Builds).
