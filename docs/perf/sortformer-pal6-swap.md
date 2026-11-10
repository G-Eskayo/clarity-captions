# Swapping the app's Sortformer to pal6: checklist and draft notice (#271)

pal6 passed the ship rule on both test sets ([speaker-scoreboard.md § Step 2](speaker-scoreboard.md#step-2-compressed-builds)).
This page is the swap, prepared but not applied: NOTICE.md and the in-app credit describe the model that actually
ships, so they change in the same PR that swaps the file, not before.

## The file

Only the scored build ships (k-means palettization isn't repeatable; a rebuild is a new, unscored build).

| | |
|---|---|
| Where it is | parked on the 2012 mini: `~/.agents/bin/marvin-cold ensure ~/sortformer-271/pal6` |
| Compiled tree sha256 | `08452c19fb78b1070dbca09d0831dda2c8565ba2d9392e68a937f0a456d2f0eb` |
| Head weights (`model1/weights/1-weight.bin`) sha256 | `29c69b1a438fd3eef8d8a994bbb6312558626b58d30ae00a31c3c7bdf74cf9a1` |
| Size | 92.6 MB on disk, 87.7 MB zipped |
| Made from | the shipped fp16 (tree `aeafa01aba595d61…`), recipe `pal6` in `scripts/engine-eval/sortformer_mil` |

## Steps

1. **Hosting (Gil's call, on #271):** where `scripts/fetch-diarizer-models.sh` fetches it from. The script then
   pins the file's sha256 instead of following a Hugging Face branch.
2. **On a real iPhone:** the app with pal6 bundled loads the model and labels speakers in a live session. The
   numbers so far are the M4's Core ML only. Check: the model loads (int8 crashed at load on the Mac, so this is the
   first thing to see), labels appear on a two-person conversation, and the memory and heat in a 10-minute session
   aren't worse than fp16's on the same phone.
3. **Notice and credit:** apply the draft below to `NOTICE.md`, `Licenses/Sortformer/NOTICE.txt` and the Sortformer
   note in `Packages/CaptionCore/Sources/CaptionCore/ThirdPartyNotice.swift` (with its string in
   `Localizable.xcstrings`), and extend `ThirdPartyNoticeTests` the way the Parakeet credit's "6 bits" check works.
   The Credits page text changes, so that PR needs screenshots.
4. **ADR 0014:** record the swap under the step 2 section.

## Draft: what changes in the notices

The agreement allows Derivative Models. It asks that the agreement and the Notice line go with them, which already
happens. The note says what we changed, the same way the Parakeet credit does.

`NOTICE.md`, Sortformer **Note**, replacing "bundled in the application unchanged (16-bit weights)…":

> **Note:** Converted to Apple Core ML format by FluidInference
> ([diar-streaming-sortformer-coreml](https://huggingface.co/FluidInference/diar-streaming-sortformer-coreml)).
> Changed for Seal Speak: the main network's weights are compressed to 6 bits (k-means palettization, one table per
> weight tensor); the small front-end stage and everything else are as converted. Bundled with a `Sortformer/NOTICE.txt` beside it carrying the
> Notice above. The conversion's own page labels it CC BY 4.0; the license NVIDIA grants on the model is the
> agreement below.

`Licenses/Sortformer/NOTICE.txt`, second paragraph:

> Sortformer streaming speaker diarization, 4 speakers, v2.1 (nvidia/diar_streaming_sortformer_4spk-v2.1),
> converted to Core ML by FluidInference, and changed for Seal Speak: its weights are compressed to 6 bits.
> Bundled in Seal Speak as the speaker-labelling model.

`ThirdPartyNotice.swift`, Sortformer note:

> NVIDIA speaker-diarization model converted to CoreML format by FluidInference. Changed for Seal Speak: its weights
> are compressed to 6 bits. Licensed by NVIDIA Corporation under the NVIDIA Open Model License
