# Design: switch captions to Parakeet Ultra 6-bit (#150)

Design for #150 "[E] Switch captions to Parakeet Ultra: iPhone checks, then an ADR (from the #145 accent test)".
The decision record is [ADR 0025](../adr/0025-parakeet-ultra-caption-engine.md) (Accepted 2026-10-23). This doc
covers how: the code seam, streaming, packaging, the fallback, the iPhone checks, the tests and the task order. Gil
approved it on 2026-10-23 ("go ahead and start the parakeet code"); his answers are in Decisions at the end.

## What is already decided (Gil, 2026-10-22, #150 comments)

- **Engine:** Parakeet Ultra with its encoder palettized to 6 bits (coremltools k-means, per grouped channel, group
  16, data-free). 498 MB on disk, about 485 MB zipped, **13.8% WER** on the full EdAcc run, the same as the
  published 8-bit build. **Ultra 4-bit** (350 MB, 14.8%) is the fallback build if 6-bit fails the phone checks.
- **Ships in 1.1, as build 7**, together with the iPad and iPhone Duo work already merged in build 6 (#147).
- **Apple's SpeechAnalyzer stays in**, behind a flag, as the fallback engine.
- **Bundled** per ADR 0014, so captions work offline from the first launch.
- The compressed builds are on the M4 (`ssh gils-mac-mini`) in `~/edacc-eval/models/variants/ultra-pal6` and
  `ultra-pal4`.

Evidence behind the pick: PR #149, `docs/perf/engine-accuracy-comparison.md` (report "Size options", evidence log
E12) and `docs/perf/engine-accuracy-design.md` on `feature/145-engine-eval`.

## Patterns reused

| Need | Existing pattern | Where |
|---|---|---|
| Model ships in the app, never downloaded at runtime | ADR 0014: compiled `.mlmodelc` in the bundle, URL passed in with no default, `ModelHub.offlineMode = true`, fetch script with size + sha256 checks, project generator fails if the folder is missing | `LiveDiarizer`, `scripts/fetch-diarizer-models.sh`, `Apps/Spike/project.yml` |
| Load before Start | `CaptioningEngine.prepare(onStep:)` + `EngineWarmup` (#119) | `EngineWarmup.swift`, `CaptionSessionController.swift` |
| Fakes for the lifecycle | `CaptioningEngine` protocol with test fakes | `CaptionSessionControllerTests`, `EngineWarmupTests` |
| Finals accumulate, the volatile tail is replaced | `CaptionStream.apply(text:isFinal:speaker:range:wordEmphasis:)` | `CaptionStream.swift` |
| Speaker per caption by time overlap | `SpeakerLabelSmoother.label(start:end:segments:isFinal:)` | `SpeakerLabelSmoother.swift` |
| Lag measurement | `WordLagTracker` over word end times, `FedWallTime` | `WordLagTracker.swift`, `TranscriptionEngine.swift` |
| Loading a local Parakeet folder | `AsrModels.loadLocal(from:version:)` (already used by the #145 harness for the variants) | `Packages/EngineEval` on `feature/145-engine-eval` |
| Memory warning releases a warmed engine | `EngineWarmupHost` observes `didReceiveMemoryWarningNotification` | `Apps/Spike/Sources/EngineWarmupHost.swift` |
| Field metrics (lag, battery per 30 min, thermal) | beta report schema 1 | ADR 0023/0024, `docs/beta/metrics-schema.md` |
| Credits screen | `ThirdPartyNotice.all` + `NOTICE.md` bundled | `ThirdPartyNotice.swift`, `ThirdPartyNoticeTests` |

## Feasibility spike (done, outside the app)

**Question:** can FluidAudio 0.17.5 (the pinned revision `0b1f462`) load a custom, compressed Parakeet build from
a local folder, or does it only download its own Hugging Face models?

**Answer: yes, it loads from a local folder, with no network.** `AsrModels.loadLocal(from:version:)` is public in
0.17.5 ("Load compiled models from this exact directory without downloading or resolving a repository"). It reads
`Preprocessor.mlmodelc`, `Encoder.mlmodelc`, `Decoder.mlmodelc`, `JointDecisionv3.mlmodelc` and
`parakeet_vocab.json` from the folder for `.ultra` (corrected 2026-10-24: an earlier draft said `parakeet_v3_vocab.json`;
the integration test showed `loadLocal` needs `parakeet_vocab.json`), checks the vocabulary, and calls `MLModel(contentsOf:)`. It
never touches `ModelHub`. `AsrManager.loadModels(_:)` only stores the models.

Run on this MacBook (Apple M-series, macOS 27), nice +15, a throwaway SwiftPM package in the session scratch
directory pointed at the existing 0.17.5 checkout, with `ModelHub.offlineMode = true` and the `ultra-pal6` folder
copied from the M4:

| Measure | Result |
|---|---|
| `loadLocal`, first ever load of this folder on this Mac | **35.3 s** (Core ML compiles and specializes the palettized encoder for the device) |
| `loadLocal`, second run | **0.17 s** (cached) |
| Full decode, 15.8 s of `say` speech | 0.34-0.43 s; text correct word for word, punctuated |
| Tail-window decode every 0.5 s, fresh decoder state, window 4 / 6 / 8 / 12 s | median 0.11-0.16 / 0.12-0.16 / 0.14-0.17 / 0.16-0.20 s; p95 up to 0.50 s at 12 s |
| Process footprint after load and decode | about 50 MB (macOS does not count the mapped weights or Neural Engine memory here; this number says nothing about iPhone memory) |

Two findings that shape the design:

1. **Every decode costs roughly the same, whatever the window.** FluidAudio pads any input up to
   `ASRConstants.maxModelSamples` = 240,000 samples (15 s) because the encoder has a fixed input shape. A 4 s window
   and a 12 s window both run a full 15 s encoder pass. So the window length is an accuracy and commit-logic choice,
   and **the decode rate (hop) is what sets Neural Engine load, battery and heat**.
2. **The first load after install is slow** (35 s on the Mac). On the phone it has to happen inside first run, not
   behind the launch animation, and it can come back after an iOS update clears the cache.

Also seen: the variant folder carries a stale `config.json` copied from the published build (it says
`int8_linear_per_channel`). `loadLocal` ignores it, but the shipped folder should not carry a wrong label (task 4).

## 1. The engine seam

Today `TranscriptionEngine` does four jobs: microphone and audio routing, the 16 kHz side path (diarizer, sound
labeler, loudness), Apple's `SpeechAnalyzer`, and mapping results to `CaptionUpdate`. Only the third job changes.

```swift
/// One speech recognizer behind TranscriptionEngine. Apple's SpeechAnalyzer and Parakeet both implement it.
protocol SpeechRecognizerBackend: AnyObject, Sendable {
    var name: String { get }                       // "apple-speechanalyzer" / "parakeet-ultra-pal6"
    /// Loads the model. Never opens the microphone. Steps feed EngineWarmup.
    func prepare(onStep: @escaping @Sendable (Int) -> Void) async throws
    /// Audio format the backend wants. Parakeet: 16 kHz mono Float32 (the diarizer's format).
    var inputKind: RecognizerInput { get }         // .analyzerFormat(AVAudioFormat) or .mono16k
    func start() async throws -> AsyncThrowingStream<RecognizedPiece, Error>
    /// Called on the audio thread; must not block (enqueue only).
    func feed(_ input: RecognizerFeed)
    /// Flushes and emits the remaining words as final.
    func finish() async
    /// Frees the model. Safe to call more than once, and after a failed prepare.
    func cancel() async
}

/// Engine-neutral result: what TranscriptionEngine needs to build a CaptionUpdate.
struct RecognizedPiece: Sendable, Equatable {
    let words: [TimedWord]      // text + audio start/end in seconds since the first fed sample
    let isFinal: Bool
}
```

- `TranscriptionEngine` keeps its public API, `CaptioningEngine` conformance and the `CaptionUpdate` contract
  unchanged. It picks a backend at `init` (see the flag in section 5) and maps `RecognizedPiece` to
  `CaptionUpdate`: text = words joined, `startSeconds`/`endSeconds` from the first and last word,
  `speaker` from `SpeakerLabelSmoother`, `lagSeconds` from `WordLagTracker` over the word ends, and
  `wordEmphasis` from the loudness series over each word's range.
- The Apple backend is today's code moved, not rewritten: `SpeechTranscriber` options, the converter to
  `bestAvailableAudioFormat`, `finalizeAndFinishThroughEndOfInput` on stop. Its `AttributedString` runs become
  `TimedWord`s. (The custom vocabulary list and its `contextualStrings` plumbing are removed, D5.)
- `wordEmphasisFromResultText(_ AttributedString)` becomes a pure function over `[TimedWord]`. That is a small
  behavior-preserving refactor with its own test first.
- The Parakeet backend reads the 16 kHz mono samples `processBuffer` already makes for the diarizer, so there is no
  third converter and both models see the same samples and the same clock.
- `startReplaying(fileURL:)` (the ADR 0015 benchmark) goes through the same backend, so the latency test measures
  whichever engine is selected.
- `EngineWarmup.steps` stays 3 for the Apple path. For Parakeet, step 1 is "speech model" = `loadLocal` + one warm
  decode of 1 s of silence, so the first real decode is not the slow one.
- The Mac app (`Apps/Mac`) gets the same seam for free. Whether it bundles Parakeet in 1.1 is a decision (D6).

## 2. Streaming: committed tail-window decoding

Parakeet TDT is an offline model. FluidAudio 0.17.5's `SlidingWindowAsrManager` only emits once 11 s of chunk plus
2 s of right context exist (a 13 s floor, measured in #145), and the "true streaming" managers (`StreamingAsrManager`:
EOU 120M, Nemotron, Parakeet Unified) are other models, not Ultra. So the app decodes Ultra itself, with a small pure
committer on top of the public `AsrManager.transcribe(_:decoderState:)`.

**Loop (one serial queue, never the audio thread):**

1. Append 16 kHz samples to a buffer that keeps audio from `commitPoint - leftContext` to now.
2. Every **hop** (start at 0.5 s; see adaptive hop below), and only if the previous decode has finished, decode the
   window `[commitPoint - leftContext, now]` with a fresh `TdtDecoderState`. `leftContext` = 1.0 s, so the first
   committed-over word has acoustic context. Shift token times by the window start to get absolute times; merge
   sub-word tokens into words (FluidAudio's token timings, `▁` marks a word start).
3. Drop words that end before `commitPoint` (they belong to the context).
4. **Commit rule (LocalAgreement-2):** a word becomes final when it appears with the same text in two consecutive
   decodes, in the same position after the last committed word, and ends at least `stabilityMargin` = 0.6 s
   before the newest audio. Commit stops at the first word that fails, so finals are always a prefix.
5. **Force commit:** if the uncommitted span reaches `maxUncommitted` = 12 s (the window would pass the encoder's
   15 s limit), commit every word ending before `now - 2 s` from the latest decode, agreement or not.
6. `commitPoint` moves to the end of the last committed word. Audio before `commitPoint - leftContext` is dropped.
7. **On stop:** one last decode of the remainder, and every remaining word becomes final.

**Mapping to `CaptionUpdate` (what the screen already understands):**

| Decode output | Update emitted | How `CaptionStream` treats it |
|---|---|---|
| Newly committed words | one `isFinal: true` update, range = first to last committed word | starts before the open tail ends, so it is a revision: the words join the line's committed text and the tail closes |
| Words after them (not yet agreed) | one `isFinal: false` update, range = their span | opens the new tail (gap under 1.2 s joins the same line) |
| Nothing new | nothing | |

Both updates from one decode are sent back to back, so the main actor applies them in the same run-loop turn and the
tail does not flicker. A committed batch that spans a pause of 1.2 s or more is split there, so `CaptionStream`'s
pause rule still starts a new line in the same place. Volatile and final lines both show (ADR 0012, ADR 0018), so
finals appearing a little later than with Apple's engine does not hide words: the volatile tail shows them first.

**Latency arithmetic.** A word's volatile appearance is at most hop + decode time after it is heard (0.5 + about
0.15 s on the M4). Its final appearance needs a second agreeing decode plus the 0.6 s margin, about 1.1-1.7 s. The
#145 Mac measurement of a growing window gave 0.24 s median / 1.34 s p95 to the *correct* word. The phone figure
is what check C2 measures.

**Adaptive hop (the battery and heat lever).** `hop = clamp(1.3 × median of the last 5 decode times, 0.5 s, 1.5 s)`,
then doubled while `ProcessInfo.thermalState` is `.serious`. If decodes get slow, the loop decodes less often instead
of queueing work. Silence gate: if the last hop's RMS is under the room-noise baseline (`LoudnessBaseline`) and
nothing is uncommitted, skip the decode. A quiet table costs almost nothing.

**Pure part, tested without a model:** the committer is a value type,
`TailCommitter.ingest(decode: [TimedWord], windowStart:, audioEnd:) -> (final: [TimedWord], volatile: [TimedWord])`,
plus `AdaptiveHop.next(decodeTimes:thermal:)`. The decoding loop around them is thin.

## 3. Diarizer and sound labeler

Nothing changes in either. Both keep reading the 16 kHz mono side path in `processBuffer`, on their own serial
queues, on the same `FedAudioClock` time base. Parakeet's word times are also on that clock (seconds since the
first fed sample), so `SpeakerLabelSmoother` labels by the same overlap rule and `SoundLabeler` events interleave
as now.

What does change is load on the Neural Engine: Sortformer runs on every buffer and Parakeet runs a 15 s encoder pass
every hop. Check C3 measures them together; if they contend, the first lever is the adaptive hop, the second is
moving Sortformer to `.cpuAndGPU` (only in the foreground: GPU work is not allowed in the background).

## 4. Model packaging (no blobs in git)

**Reuse ADR 0014 as is:** a fetch script puts the compiled model folder in the gitignored
`Apps/Spike/Resources/Models/`, verifies size and sha256 of every file, and `project.yml` lists the folder as a
resource with no "optional" flag, so `xcodegen generate` fails when it is missing.

- New script `scripts/fetch-asr-models.sh` (or a second section in the existing script, D3), with
  `VARIANT=ultra-pal6` at the top. Switching to 4-bit is that one line plus nothing else, because `loadLocal` takes
  the folder as is.
- The folder ships as `Resources/Models/ParakeetUltra/` containing the four `.mlmodelc` components,
  `parakeet_vocab.json`, `NOTICE.txt` and a corrected `variant.json`; the stale `config.json` and the unused,
  byte-identical `parakeet_v3_vocab.json` are dropped.
- A checked-in manifest `scripts/models/ultra-pal6.sha256` lists every file's size and sha256, generated once from
  the M4 copy. The script refuses anything that doesn't match, whatever the host serves. This also closes ADR
  0014's open follow-up (the Sortformer fetch is still unpinned on `main`).
- `BundledModelsTests` (already exists for Sortformer) gains the same check for the ASR folder.

**Where the 6-bit build is hosted (nothing has been uploaded; Gil picks, D2):**

| Option | For | Against |
|---|---|---|
| **A. GitHub Release asset on G-Eskayo/clarity-captions** (one zip, about 485 MB; the limit is 2 GB per file) | Same account and repo as the code; no new service; the sha256 manifest pins it; release notes carry the CC BY attribution | Release assets can be replaced by the owner (the manifest catches it); a zip, so the script unzips |
| B. Hugging Face model repo under Gil's account | Same tooling as the Sortformer fetch; per-file LFS sha256; a model card is the natural place for attribution; pin by commit SHA | A new account or org to keep up; a second place to look |
| C. Rebuild at fetch time from the published fp16 export with `compress_parakeet.py` | Nothing new hosted | Needs about 10 GB scratch, a Python 3.12 + coremltools env and about 10 min; k-means may not be bit-identical across runs, so sha256 pinning breaks |
| D. Copy from the M4 (`rsync --checksum` from `~/edacc-eval/models/variants/`) | Zero setup; builds already happen on the Mini | A fresh clone elsewhere cannot build; the Mini becomes the only copy of a shipping input |
| E. Git LFS in this repo | One place | GitHub's free LFS quota is 1 GB storage and 1 GB a month of bandwidth; a few clones use it up |

**Recommendation: A**, with D as the script's fallback source when `SEAL_MODEL_SOURCE=mini` is set (useful on the
Mini, where the folder already sits). The upload is a one-time step for Gil (or an agent with Gil's explicit
go-ahead in that session), done after the corrected folder and manifest are reviewed.

**Size.** The release `.app` was 247 MB with Sortformer; with Ultra 6-bit it becomes about 745 MB on disk. The App
Store download is compressed (about 485 MB zipped for the model). iOS asks before downloading apps over 200 MB on
cellular; that already applied at 247 MB, so nothing new for the user. Apple-hosted Background Assets (asset packs
fetched before first launch, iOS 26) would keep the binary small, but it adds a new download path and App Store
Connect setup; it is a later option, not for build 7.

## 5. Feature flag and fallback

**The flag.** `CaptionEngineChoice` (`.parakeet` / `.apple`), stored in `UserDefaults`, default `.parakeet` in build
7. It is changed from the hidden developer panel only. There is no setting for the user (ADR 0013, radical
simplicity). Beta reports gain an `engine` field (schema 1 is additive) so the Mini's per-device view (ADR 0024) can
split lag, battery and thermal by engine.

**Apple's speech asset keeps installing in first run** (today's `SpeechModelInstaller` step), so the fallback works
offline too (D4).

**Fallback triggers.** The rule: never show an error the user can't act on; captions keep flowing.

| Trigger | When checked | Action |
|---|---|---|
| Model folder missing or `loadLocal` throws | `prepare` | use Apple for this launch; log the reason in diagnostics and the beta report |
| First decode fails or returns nothing for 10 s of speech (RMS above baseline) | first 10 s of a session | switch the backend to Apple mid-session (below) |
| Memory warning (`didReceiveMemoryWarningNotification`) while running | any time | finish the Parakeet backend (commit what it has), switch to Apple for the rest of the session; next session tries Parakeet again |
| `os_proc_available_memory()` under the floor before load (start: 400 MB, tuned by C3) | `prepare` | use Apple for this session |
| `thermalState == .serious` | on change | hop doubled (section 2) |
| `thermalState == .critical` | on change | switch to Apple for the rest of the session |
| 2 Parakeet fallbacks in 24 h on this device | launch | stay on Apple for 24 h, then try again |

**Mid-session switch.** The microphone tap, the diarizer, the sound labeler and the clock all stay up; only the
backend changes. The old backend's `finish()` emits its remaining words as final; the new one starts on the next
buffer. Apple's analyzer warm-up (about 1 s with the asset installed) is the gap; the volatile tail shows nothing
new during it, so no words are invented or lost from the screen. A gap of up to 1 s of audio may go uncaptioned in
the switch, which is accepted for a rare event and logged.

## 6. License and NOTICE (CC BY 4.0)

Checked on Hugging Face today (2026-10-22): `moondream/parakeet-ultra` (sha `73175eb`), `nvidia/parakeet-tdt-0.6b-v3`
(sha `541d1f9`) and `FluidInference/parakeet-ultra-coreml` (sha `95eaa59`) all declare `cc-by-4.0`.

CC BY 4.0 asks for credit, a link to the license, and a note of changes. Add:

- **NOTICE.md:** a "Parakeet Ultra" section: weights by Moondream (`moondream/parakeet-ultra`), a post-training of
  NVIDIA Parakeet TDT 0.6B v3; Core ML conversion by FluidInference; **changes: the encoder's weights were
  compressed to 6 bits (k-means palettization) for Seal Speak**; license link and text, as the Sortformer section
  does.
- **`ThirdPartyNotice.all`:** an entry `parakeetultra`, "CC BY 4.0", with the same note in one sentence and the
  source URL; `ThirdPartyNoticeTests` and the localization catalog updated.
- **The model folder:** `NOTICE.txt` travels with it (already written by `compress_parakeet.py`).
- **The release asset or model card** (if A or B): the same attribution text.

## 7. iPhone check plan

On Gil's iPhone 17, iOS 26, a Release build from the design branch's implementation, before build 7 is uploaded.
Each check runs **both engines on the same phone in the same build** (the flag), because ADR 0015's baseline file
still says TBD and its 10% rule exempts model swaps: Apple's engine, measured the same day, is the baseline.

| # | Check | How | Pass | Fail |
|---|---|---|---|---|
| C1 | Loads offline on iOS 26 | Fresh install, airplane mode, first run, then a relaunch | Captions appear; cold first load ≤ 60 s and inside the first-run screen; warm load ≤ 3 s | Load throws, any network attempt, or cold load > 120 s |
| C2 | Latency (ADR 0015) | Developer-panel replay of the same 20 s fixture through both engines, 3 runs each, Release | Parakeet median word lag ≤ Apple median × 1.10; decode p95 < 0.5 s | Median > Apple × 1.25, or decode p95 > 1.0 s (hop can't keep up). Between 1.10 and 1.25: Gil decides with the accuracy gain in view |
| C3 | Memory with Sortformer loaded | Xcode memory gauge + `os_proc_available_memory()` logged every 10 s, 20 min of live speech, then lock and background per today's behavior (ADR 0020 deferred, ADR 0019 screen awake) | Peak footprint ≤ 1.2 GB, no memory warning, available memory never under 500 MB | A jetsam kill, or a memory warning in steady state. Peak above 1.2 GB with no warning: re-run with 4-bit |
| C4 | Battery and heat | 60 min table session, speech played from a speaker at 1 m, screen on, same start charge (80-90%) and room temperature, once per engine | Battery drop ≤ 1.3 × Apple's and ≤ 15% per hour; thermal state never `.serious` | `.critical` at any point, or drop > 1.5 × Apple's. `.serious` with the hop doubling holding it: Gil decides |
| C5 | Real-world accuracy | Test plan E3 or E4 (restaurant or simulated restaurant), record raw audio, score both engines on it offline with the #145 scorer | Parakeet WER ≤ Apple's on the same recording | Parakeet worse than Apple by more than 2 points |
| C6 | Fallbacks fire | Delete the model folder in a dev build; Xcode "Simulate Memory Warning"; Xcode device conditions thermal `.serious` and `.critical` | Each trigger takes the documented action, captions keep flowing | Any trigger shows an error or stops captions |
| C7 | Size | App Store Connect processed size for the build | Recorded in the PR | (information only) |

If 6-bit fails C3 or C4, swap `VARIANT=ultra-pal4` and re-run C2-C5. If 4-bit fails too, build 7 ships the seam with
the flag defaulting to `.apple`, and the switch moves to 1.2 (D1).

## 8. Test plan (TDD order)

Pure first, each red before green, real collaborators where cheap, inputs chosen to break things:

1. **`TailCommitterTests`** (new, pure): two agreeing decodes commit a prefix; a disagreement in the middle stops the
   commit there; words inside `stabilityMargin` never commit; context words before `commitPoint` are dropped and
   never re-emitted; force commit at 12 s uncommitted; a decode that returns nothing commits nothing; the flush on
   stop commits everything; window offset applied once (times absolute); a word repeated across the boundary ("the
   the") is not double-committed or swallowed; 10,000 random decode sequences keep finals a prefix that never
   changes.
2. **`TokenWordMergeTests`** (pure): FluidAudio `TokenTiming`s with `▁` word starts become words with the right
   start/end; punctuation stays attached; empty input.
3. **`AdaptiveHopTests`** (pure): clamps to 0.5-1.5 s; doubles under `.serious`; ignores a single outlier (median).
4. **`WordEmphasisTests`** (refactor guard): the new `[TimedWord]` emphasis function gives the same levels as
   today's `AttributedString` version on the same inputs, written before the refactor.
5. **`EngineFallbackPolicyTests`** (pure): each trigger in section 5 maps to the right action; 2 fallbacks in 24 h
   pin Apple; a memory warning while on Apple does nothing.
6. **`CaptionUpdateMappingTests`**: a committed batch then a volatile tail fed into a real `CaptionStream` gives one
   line with the right text, a pause ≥ 1.2 s inside a batch starts a new line, a speaker change splits as #91 does.
7. **`TranscriptionEngineBackendTests`** with a fake backend: `CaptioningEngine` lifecycle rules still hold
   (failed prepare frees, stop twice is safe, mid-session switch keeps the stream open and emits the old backend's
   finals first).
8. **`BundledModelsTests`**: the ASR folder exists, has every file in the manifest, and the fetch script's manifest
   matches. **`ThirdPartyNoticeTests`**: the Parakeet entry exists and NOTICE.md mentions the changes.
9. **Opt-in integration** (`CAPTION_PARAKEET=1`, needs the fetched model): load from the bundle path with
   `ModelHub.offlineMode = true`, replay the latency fixture, assert text contains the fixture's words and
   committed text never shrinks. Then the ADR 0015 benchmark (`CAPTION_LATENCY=1 -c release`) for both engines.

## 9. Space and time complexity

- **Audio buffer:** bounded by `leftContext + maxUncommitted` ≤ 13 s of 16 kHz Float32 = 832 KB, O(1) in session
  length. Force commit guarantees the bound.
- **Per decode:** constant, because the encoder input is padded to 15 s; the TDT decoder is O(tokens in window), at
  most about 190 encoder frames. The committer's agreement check is O(words in window) (≤ about 40). Per session:
  O(session seconds / hop) decodes. At hop 0.5 s that is 7,200 decodes an hour; at 1.0 s, 3,600.
- **Redundancy:** each second of speech is encoded about 2 × 15 = 30 times at hop 0.5 s (the price of an offline
  model in a live loop). The silence gate removes it for quiet stretches. This is the number to watch in C4.
- **Model memory:** O(1): one Parakeet (≈ 500 MB of weights, mapped) + Sortformer (≈ 241 MB). Apple's analyzer is
  not loaded while Parakeet runs; only one recognizer is ever live (EngineWarmup's rule).
- **Loudness series:** unchanged (`loudnessTimeSeries` grows O(session) today; not made worse here. It is an
  existing O(N) scan per word, noted for a separate ticket).
- **Disk:** +498 MB in the app bundle; the fetch script's download is ≈ 485 MB once per clone.

## 10. Risks

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Heat and battery: 30× re-encoding plus Sortformer on the Neural Engine for an hour | Medium | Phone warm, session cut short, thermal throttling raises lag | Adaptive hop, silence gate, `.serious` doubling, `.critical` fallback; 4-bit doesn't cut compute, so the real lever beyond these is a shorter fixed-shape encoder export (e.g. 6 s), which is new export work (not build 7) |
| First load after install takes 30-60+ s on the phone | High | First run looks stuck | Run it in the first-run flow with its own step and progress, not behind the launch animation; measure in C1 |
| Memory with two large models on an 8 GB phone | Low-medium | Jetsam kill mid-conversation | C3; fallback on memory warning; 4-bit build |
| iOS 18+ palettization ops on the iPhone Neural Engine fall back to CPU | Low | Slow decodes | C2 decode p95 catches it; the encoder's compute-unit placement shows in Instruments' Core ML template |
| Locale: the app runs en-US today; Ultra is English-tuned | Low | A non-English locale gets worse captions | Non-English locales use Apple (one line in the flag logic) |
| Hosting choice slips | Medium | Build 7 can't be built from a clean clone | Option D (Mini copy) unblocks the build on the Mini meanwhile |
| Latency budget has no committed baseline (ADR 0015's file says TBD) | Certain | "10% over what?" | Apple measured on the same phone in the same build is the baseline (C2); fill the baseline file as part of task 12 |
| App Review asks about the larger download | Low | Delay | Nothing to declare; the size is the model, offline by design |

## 11. Ordered task list

Doc-first: approved by Gil on 2026-10-23.

1. Gil reviews this doc and ADR 0025; answers D1-D7. ADR 0025 goes to Accepted. **Done 2026-10-23.**
2. ~~Measure Apple's engine on the phone beforehand.~~ Dropped: both engines are measured on the same Parakeet build
   the same day in step 10.
3. TDD: `TailCommitter`, token-to-word merge, `AdaptiveHop`, `EngineFallbackPolicy` (tests 1-3, 5).
4. Packaging: clean the `ultra-pal6` folder (drop `config.json` and `parakeet_v3_vocab.json`, correct `variant.json`),
   generate the sha256 manifest, write `scripts/fetch-asr-models.sh` with the chosen source and the Mini fallback,
   add the folder to `project.yml`, extend `BundledModelsTests`. Gil (or an agent with Gil's go-ahead) uploads the
   asset per D2.
5. TDD refactor: word emphasis over `[TimedWord]` (test 4), then extract the Apple backend behind
   `SpeechRecognizerBackend` with no behavior change; full suite green; latency benchmark unchanged.
6. Parakeet backend: `loadLocal` from the bundle URL (no default, `ModelHub.offlineMode = true`), the decode loop
   around the committer, warm decode in `prepare`, first-run step for the cold load (tests 6-7).
7. Flag, fallback triggers and the mid-session switch; `engine` field in beta reports; developer-panel toggle.
8. NOTICE.md, `ThirdPartyNotice` entry, localization strings, credits screen check.
9. Opt-in integration test and ADR 0015 benchmark on the Mac for both engines (test 9).
10. iPhone checks C1-C7 on 6-bit; screenshots and numbers into the PR. If C3/C4 fail, repeat on 4-bit.
11. Build 7 of 1.1 (version stays 1.1), Gil uploads to TestFlight; watch the beta report view split by engine.
12. Fill `docs/perf/caption-latency-baseline.md` with both engines' phone numbers; update the Versions page story
    (#151) if the switch ships.

## Decisions (Gil, 2026-10-23)

- **D1. If both 6-bit and 4-bit fail the phone checks:** not decided now. If Parakeet fails, Gil decides with the
  real phone numbers in front of him. (The seam and the flag are built either way, so every option stays open.)
- **D2. Hosting:** A. GitHub Release asset on G-Eskayo/clarity-captions, sha256 manifest in the repo, the Mini copy
  as the fallback source (`SEAL_MODEL_SOURCE=mini`).
- **D3. Fetch scripts:** two. `fetch-diarizer-models.sh` stays as is; new `fetch-asr-models.sh`.
- **D4. Apple's speech asset:** keeps installing in first run, so the fallback works offline.
- **D5. Custom vocabulary list: removed from the app entirely.** `VocabularyList`, `VocabularyStore`, the
  `contextualStrings` passed to `TranscriptionEngine`, their tests and their mentions in the docs are deleted as
  part of this work. It is not an option, not a later ticket, and not a future Parakeet feature.
- **D6. Mac app:** stays on Apple's engine in 1.1.
- **D7. Hop:** 0.5 s adaptive at the start of the phone checks.

**How the checks run:** on a real Release build installed on Gil's iPhone by cable, with Parakeet on and both
engines in the build behind the developer flag. Both engines are measured on that same build, on the same day.
There is no separate Apple baseline run beforehand (this replaces task 2's separate step).
