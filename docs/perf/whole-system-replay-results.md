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

So the Mac rules out, for clean audio: build 10's code outside the engine, and a Parakeet that is plainly worse
than Apple on the live path. It leaves the things only the phone and the room have (see the design doc's device-run
list): room noise, the phone's mic and audio session, translation into the ear, voice match, real memory pressure.

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

## Next

- **Noise.** Mix room noise (restaurant, TV, car) into these same recordings and rerun A, C, D: the cheapest test of
  whether Parakeet's live path degrades faster than Apple's in a room. Needs a noise set with a licence that allows it.
- **The device run** (design doc): build 10 on the demo phone, with translation, ear and voice match as the owner
  had them, the beta report's `engine` and `engineFallback` logged.
- **The owner's session data** (design doc slot).
- **Separate tickets worth opening:** a memory warning switches the whole session to Apple silently; the live path's
  chunk boundaries cost Parakeet 2.6–3.4 points; FluidAudio is not pinned for the app (design doc, Builds).
