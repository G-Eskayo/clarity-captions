# Speaker label stability (#91)

The owner, talking alone on an iPhone 17 Pro, was labeled Speaker 1, then Speaker 2, and sometimes Speaker 3.
This records what was measured, what caused it, and what changed.

## How it's measured

`SpeakerStabilityReplayTests` (opt-in, needs the bundled model and macOS `say`):

```sh
cd Packages/CaptionCore
CAPTION_INTEGRATION=1 swift test --filter SpeakerStabilityReplay          # add CAPTION_STABILITY_DUMP=1 for every label and segment
CAPTION_DIARIZER_MODEL_BALANCED=/path/SortformerNvidiaLow_v2.1.mlmodelc ... # also compare another Sortformer variant
```

Synthetic speech goes through the real `LiveDiarizer` in the app's buffer size (~85 ms). At each moment the app
would label a caption (a live result about every 0.5 s, the final about 1 s after a phrase ends), the label is
computed from the segments the app would have had then, and fed into `CaptionStream` as the app does. The
transcript it ends with is scored word by word against who really spoke.

Material: two one-voice monologues (~70 s, pitch and pace changing every sentence, one laugh), and three
two-person dialogues (clearly different voices, two women, and a near-identical pair).

**Synthetic voices are not a phone on a table in a room.** This separates "the labeling logic is unsteady" from
"the room confuses the model". It does not replace a check on a real device.

## What causes it

From the dumps (every caption label plus the diarizer's final segments):

1. **The model puts whole stretches of one voice in another slot after a pitch or pace change.** These are
   multi-second, *finalized* segments: Samantha's three highest-pitched sentences (including the laugh) went to
   slot 2; Daniel's sentences spread over all four slots. This is the main cause and none of the changes below
   fix it: on timing alone it looks exactly like a second person taking a turn.
2. **Live lines were relabeled by brief segments**: sub-second segments of another slot (and tentative segments
   later revised) flipped the label of a line while it was being spoken.
3. **`CaptionStream` relabeled whole lines.** The next person's first words often arrive before their speaker is
   known, so they join the previous line; when the label then arrived, the *whole* line, the previous person's
   words included, switched to the new speaker.
4. **Slot numbers were shown raw**, so two people could be "Speaker 1" and "Speaker 3".

## What changed

- `SpeakerLabelSmoother` (replaces `SpeakerAligner` in `TranscriptionEngine`, one per session): ignores segments
  under 0.5 s when longer ones cover the caption; keeps a live utterance's label until another slot holds 1 s of
  it (a new utterance, or a final, goes to whoever holds most of it); numbers speakers in order of appearance; a
  live scrap of an unseen slot can't take a number.
- `CaptionStream`: words that joined a line before their speaker was known move to their own line when their
  speaker turns out to be someone else.

## Results (shipped Sortformer fastV2_1)

Mislabeled = transcript words under a label that isn't their speaker's (one label per person, by majority).
Live relabels = a live line's label changing while it is spoken.

| Material | Before: mislabeled · speakers in transcript · highest "Speaker N" live · live relabels/min | After |
|---|---|---|
| One voice (Samantha) | 34% · 2 · 3 · 3.7 | **19%** · 2 · **2** · **2.8** |
| One voice (Daniel) | 53% · 4 · 4 · 8.1 | 56% · 4 · 4 · **4.5** |
| Two voices (Samantha/Daniel) | 0% · 2 · 3 · 1.4 | 0% · 2 · 3 · 1.4 |
| Two women (Samantha/Flo) | 18% · 3 · 4 · 0.0 | 18% · 3 · **3** · 0.0 |
| Near-identical voices (Eddy US/UK) | 46% · 1 · 1 · 0.0 | 46% · 1 · 1 · 0.0 (the model hears one person) |

Turn delay (start of a new person's speech to their correct label) unchanged: median 0.87–0.93 s; worst case
1.00 → 1.16 s on the two-women dialogue. No mixed lines in any run after the change.

## Tried and rejected

- **"A new speaker must prove itself"** (a never-shown slot needs 1.2–4 s of speech before it appears): fewer
  speakers on one voice at 4 s (Daniel 4 → 3), but merged the next person's first words into the previous
  person's line (two voices 0% → 7–18% mislabeled, one missed turn).
- **Holding the previous speaker across utterances** (not just within one): same merging problem; on the
  two-voice dialogue the speaker changes between lines fell from 11 to 2, i.e. turns merged.
- **Sortformer balancedV2_1** (larger FIFO, same ~1 s latency, a separate 235 MB model): no better on this
  material (Samantha 48% mislabeled, Daniel 4 → 3 speakers) at ~2.5× the compute (8× vs ~20× real time on a Mac).

## What would fix the main cause

Re-identifying voices across slots (comparing a speaker embedding of each new slot's speech with the voices
already shown, and merging when they match) — a separate model and an owner decision on size, not a tuning change.
First step: record the owner talking alone and with one other person on the phone, and replay those here.
