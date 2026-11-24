# Car-call test set (#303, part of #302)

A synthetic version of the call that went wrong: someone phones in, the call plays through the car's speakers, the
iPhone running Seal Speak hears it through its mic, someone else in the car talks too, and there's road noise.
Every step is file processing, so nothing is ever played or recorded. Real recordings are #302 step 3.

## What one scene is

```
caller clip (EdAcc, 16 kHz) ─► 8 kHz, 300–3,400 Hz ─► codec round trip ─► 16 kHz ─► car door speaker ─► cabin ─┐
person in the car (another EdAcc conversation, full band, short near-field response, +6 dB) ───────────────────┼─► mix
synthetic road noise (rumble, engine harmonics, tyre band, slow swells) scaled to the target SNR ────────────────┘
```

- **Codec:** AMR-NB 12.2 kbit/s when ffmpeg has `libopencore_amrnb`, otherwise G.711 μ-law (`pcm_mulaw`).
  Homebrew's ffmpeg has no AMR-NB, so the first run used μ-law. μ-law is gentler than AMR-NB, so these numbers are
  an optimistic bound for a narrowband call.
- **Speaker and cabin:** a 150 Hz high-pass, a 2.5 kHz cone peak and an 800 Hz dip, then a synthetic cabin
  impulse response (direct path, early reflections at 2–9 ms, RT60 0.12 s). It stays linear on purpose, because
  distortion would put energy back above the call band.
- **Road noise:** fully synthetic, so there's no licensing question. Brown rumble under 400 Hz, engine harmonics at
  28–40 Hz with drifting RPM, a pink layer and a 600–1,200 Hz tyre band that falls inside the call band, all under
  0.2–0.6 Hz swells. No recorded noise or impulse responses are used.
- **SNR:** far voice power over road-noise power, measured over the far voice's span as it arrives at the phone
  (after the speaker and cabin). The near talker sits 6 dB above the far voice, each measured over its own span.
- **Layout:** caller first, a 0.4 s gap, then the person in the car answers. Turns don't overlap (see "Limits").

Each pair gives seven clips:

| condition | what it is |
|---|---|
| `clean-far` | the caller's clip untouched: the engine's own baseline |
| `clean-near` | the in-car talker's clip untouched |
| `phone` | the caller through call + speaker + cabin only (no noise, no second talker): the channel on its own |
| `snr20` … `snr0` | the full scene at that SNR |

## Scoring

The engine hears each whole scene in one pass, as the app would. `car_call.score` aligns the hypothesis once
against both references in the order they're heard (the same `edacc_eval` normalizer and minimum-edit alignment
as every other result). Each error is charged to the voice whose words it hits, and an inserted word goes to the
voice just before it. WER is pooled per engine, condition and voice. The 95% interval is a bootstrap over pairs.

## Rerun

```bash
CC_REPO=~/Developer/cc-303 scripts/engine-eval/car_call/run.sh
```

It picks the pairs from shard 001's manifest (seeded: one caller per speaker, the in-car talker from a different
conversation, no clip used twice) and rsyncs only those clips from `mac-mini-2012`. Then it builds the set into
`~/Library/Caches/seal-car-call/set` (about 80 MB for 30 pairs), runs `engine-eval run` with Parakeet Ultra and
Apple SpeechAnalyzer, and writes the table. The same seed rebuilds byte-identical audio. Settings come from the
environment: `CC_PAIRS`, `CC_SNRS`, `CC_SEED`, `CC_ENGINES`, `CC_CACHE`, `CC_MODELS`. Parakeet Ultra needs
`~/edacc-eval/models/fluidaudio/parakeet-ultra`, so bring it back with `marvin-cold ensure` if it's parked.
Don't commit audio. When you're done, delete the set with `rm -rf ~/Library/Caches/seal-car-call`.

Tests: `cd scripts/engine-eval && python -m pytest tests/test_car_call.py`. They cover determinism, the band
limit above 4 kHz, SNR within ±0.5 dB, the near talker's level and full band, references carried through, and
per-voice error attribution.

## Limits

- This is the bare engine on files, not the app's live path (#273). The live path adds streaming windows,
  Sortformer speaker labels and the engine switch on memory warnings (#284).
- The noise and cabin are synthetic, and the codec is μ-law, not AMR-NB. HD Voice (wideband, 50–7,000 Hz) isn't
  modelled.
- The speakers take turns. Overlapping talk (the in-car person talking over the caller) isn't in this set yet.
