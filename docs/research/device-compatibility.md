# Device compatibility: which iPhones, iPads and Macs Seal can support

Researched 2026-10-09. Every claim in the detail sections is labeled:
- **[Apple]**: Apple documentation, a WWDC session, an Apple support page, or an answer marked as Apple's on the
  developer forums.
- **[Anecdotal]**: other developers' reports (forums, GitHub issues, blogs). These are real cases, not promises.
- **[Repo]**: checked in this repository on 2026-10-09.
- **[Inferred]**: our reasoning from the above, not stated anywhere. Each one comes with a test that settles it.

## In plain words

Seal does three things at once: it turns speech into text (Apple's speech engine), it works out who is talking (the
speaker model, Sortformer), and it notices sounds like a doorbell (Apple's sound classifier). The sound part runs on
anything. The other two need newer hardware than iOS 26 itself does.

**Apple's new speech engine (`SpeechTranscriber`) only runs on newer chips.** Apple says it has "hardware
requirements" and that it runs on A16 iPads. It doesn't publish a list. Developers report that it works on every
iPhone from the **iPhone 12** onward and does **not** work on the **iPhone 11 family or the iPhone SE (2nd
generation)**, even though those phones run iOS 26 and iOS 27. The same line seems to hold on iPad: iPads with an
A14 chip or newer should work, and older ones (A12/A13) don't.

**Apple offers a second, older engine for exactly those devices (`DictationTranscriber`).** It is fully on-device,
plugs into the same Apple framework Seal already uses, and gives the same kind of live, still-changing captions. It
is the engine behind the keyboard's dictation button. It is less accurate in Seal's real setting: several people
talking at a restaurant table, some of them away from the phone. Apple says the new engine was built for that
setting and the old one for short dictation. Using it as a backup costs only a little code (about a day, plus
testing).

**Today Seal shows a plain "Seal can't run on this device" screen on those older devices** (#80, "Check the device
can run the speech engine"). That is safe for App Review. It also means someone with an iPhone 11 gets nothing.

**Nobody has published speed numbers for the speaker model on older iPhones.** FluidAudio, the speaker-model
library, publishes Mac numbers only, and those are hundreds of times faster than real time. Older phones will be
slower, but probably still fast enough. We need to measure it, not assume it. If the speaker model ever falls behind
on a device, the rule is: **captions never wait for speaker labels**. The labels switch off for that conversation,
and the captions carry on at full speed.

### The support matrix

| Tier | What the person gets | iPhone | iPad | Mac (later) |
|---|---|---|---|---|
| **1. Full** | Live captions, speaker labels, sound labels | iPhone 12, 12 mini, 12 Pro/Pro Max, iPhone 13 family, iPhone SE (3rd gen), iPhone 14, 15, 16, 16e, 17, 17e, Air, all Pro models | iPad (10th gen), iPad (A16), iPad Air (4th gen and later, M-series), iPad mini (6th gen), iPad mini (A17 Pro), iPad Pro with M1 or later | Any Mac with Apple silicon (M1 or later, MacBook Neo) |
| **2. Reduced** (only if we build the backup engine) | Live captions from the older engine. Sound labels. Speaker labels only if the phone keeps up | iPhone 11, 11 Pro, 11 Pro Max, iPhone SE (2nd gen) | iPad (8th and 9th gen), iPad mini (5th gen), iPad Air (3rd gen), iPad Pro 11-inch (1st and 2nd gen), iPad Pro 12.9-inch (3rd and 4th gen) | none |
| **3. Says it can't run** (today's behavior for tier 2) | One clear screen explaining this device can't run Seal's captions. No Start button | same as tier 2 if no backup engine | same as tier 2 if no backup engine | Intel Macs on macOS 26 (better: don't offer the Mac app to Intel Macs at all) |
| **4. Can't install** | The App Store won't offer Seal | iPhone XS, XR and older (no iOS 26) | iPad (7th gen) and older, iPad Air (2nd gen) and older, iPad mini 4 and older, first-generation 10.5/12.9 iPad Pro and older | Macs that can't run macOS 26 |

How sure we are: tier 1 iPhones from the iPhone 12 onward are confirmed by developers' tests. iPads with A14/A15
chips are an inference from the iPhones with the same chips, and need one real test. The 4 GB devices in tier 1
(iPhone 12 and 12 mini, 13 and 13 mini, SE 3rd gen, iPad 10th gen, Air 4th gen, mini 6th gen) are the ones most
likely to struggle. They are the real floor, and the most important devices to borrow.

### Recommendations

1. **Ship v1 with tiers 1, 3 and 4 as Seal works today**: full experience on iPhone 12 and later, and the plain
   "can't run" screen on older devices. Don't add the backup engine before 25 October. It's small, but anything that
   touches the caption path needs a real-device test pass, and the deadline is for your mother's iPhone 17.
2. **Build the backup engine (tier 2) as the first update after launch (1.1).** It's the cheapest way to turn "can't
   run" into "works" for the iPhone 11 family, the SE 2, and the older iPads. Those are the devices older people
   are most likely to still own. Apple names this engine as the answer for older hardware.
3. **In tier 2, speaker labels go on only if the device proves it can keep up.** Seal times the speaker model during
   the first few seconds of each conversation. If it is too slow, labels stay off for that conversation and the
   captions are untouched. This is how "no lag or hesitation" holds on every device: the core feature never waits
   on the extra one.
4. **Don't use the App Store's device-restriction key.** The only modern option (`iphone-performance-gaming-tier`)
   would shut out the iPhone 12, 13 and 14 and the standard iPhone 15, which run Seal perfectly well, and on iPad it makes the system treat Seal
   as a game. Two notes. Once v1 ships without a restriction key, a later update can't add one. And a restriction
   wouldn't stop App Review from testing on an iPad anyway. Say it in the description instead: "Full captions need
   iPhone 12 or later, or an iPad with an A14 chip or later."
5. **Keep the speed budget per tier, not one number for all devices.** ADR 0015's "within 10% of baseline" is
   measured against a baseline on one device. Each tier gets its own baseline on its own test device, and every
   device gets one absolute rule: the speaker model must process audio at least twice as fast as real time, or its
   labels switch off.
6. **Mac (later): Apple silicon only.** Build the Mac app for Apple silicon only, so Intel Macs never see it.
   macOS 27 has already dropped every Intel Mac, and the new speech engine almost certainly doesn't run on them.
7. **Borrow 3-4 devices (test plan below).** The single most useful one is an **iPhone 12, 13 mini or SE (3rd
   gen)**: the oldest, smallest-memory phone that should get the full experience.

### Lean test plan: 4 devices

| # | Device | Why | What to check |
|---|---|---|---|
| 1 | **iPhone 17** (your mother's, or yours) on iOS 26.x, then on iOS 27 | Top of tier 1, the deadline device | Release-build latency baseline for tier 1 (ADR 0015 dev panel), 30-minute dinner-table session: heat, battery drop, no slowdown late in the session |
| 2 | **iPhone 12 / 12 mini / 13 mini / SE (3rd gen)** (borrow) | Bottom of tier 1: oldest chip and 4 GB of memory | The speech engine reports available. Speaker model loads (time the first launch: the first load compiles the model and can be slow). Per-update speaker-model time. Captions don't lag behind iPhone 17 by more than a few tenths of a second. No memory crash in a 30-minute session |
| 3 | **iPhone 11 or iPhone SE (2nd gen)** (borrow) | Tier 2/3 phone | v1: the "can't run" screen appears straight away, with no spinner and no download. 1.1: backup-engine captions, speaker-model self-check result, caption quality at a table compared with device 1 |
| 4 | **iPad (9th gen)** (borrow; most common older iPad) | Tier 2/3 iPad, and the device App Review is most likely to hold | Same as device 3, plus layout in all four orientations and Split View (ITMS-90474, #82). If a tier-1 iPad (10th gen, Air 4 or newer) is easier to borrow than a 9th gen, test that instead, and rely on device 3 for the "can't run" path |

The testers you're recruiting are the cheapest way to get devices 2-4. Ask them what phone they have before
anything else. If a tester has an iPhone 11 or SE 2, that's useful, not a mismatch.

---

## Details

### 1. Which devices run which OS

**iPhone, iOS 26** [Apple, support page "How to download iOS 26", updated 2026-09-16]: iPhone 17, 17 Pro, 17 Pro Max,
17e, Air, 16e, 16, 16 Plus, 16 Pro, 16 Pro Max, 15 family, 14 family, 13 family (incl. 13 mini), 12 family
(incl. 12 mini), iPhone 11, 11 Pro, 11 Pro Max, iPhone SE (2nd generation and later).

**iPhone, iOS 27** (released 2026-09-14): same list as iOS 26; no iPhone was dropped [Anecdotal/press: 9to5Mac
2026-06-08, quoting Apple's WWDC compatibility list; one or two outlets omitted the 11 series, but 9to5Mac's
list and Apple's iOS 26 page agree]. Consequence: **iOS 27 does not remove the iPhone 11 / SE 2 problem.** Those
phones will keep installing Seal for at least another year.

**iPad, iPadOS 26** [Apple, "How to download iPadOS 26", 2025-09-17; newer M4/M5 models added since]: iPad Pro
(M4, M5), iPad Pro 12.9-inch (3rd gen and later), iPad Pro 11-inch (1st gen and later), iPad Air (M2, M3, M4),
iPad Air (3rd gen and later), iPad (A16), iPad (8th gen and later), iPad mini (A17 Pro), iPad mini (5th gen and
later).

**iPad, iPadOS 27** (released 2026-09-14): drops iPad (8th gen), iPad mini (5th gen), iPad Air (3rd gen), iPad Pro
11-inch (1st gen) and iPad Pro 12.9-inch (3rd gen) [Anecdotal/press: EveryMac, AppleInsider, 9to5Mac, June 2026].
Those iPads stay on iPadOS 26 and **can still install Seal**, because Seal's minimum is iOS 26.

**Mac, macOS 26 Tahoe** [Apple, support page 122867]: every Apple silicon Mac (incl. MacBook Neo, A18 Pro) plus four
Intel Macs: MacBook Pro 16-inch (2019), MacBook Pro 13-inch (2020, four Thunderbolt ports), iMac (2020), Mac Pro
(2019). **macOS 27** drops those four; it is Apple silicon only [Anecdotal/press: 9to5Mac 2026-05-18,
Macfixit, June 2026].

**Chip generations behind the tiers** (the hardware facts are standard Apple spec sheets; the tier line is
[Inferred] from the reports in section 2):

| Chip | Neural Engine | Devices on iOS/iPadOS 26 | Memory |
|---|---|---|---|
| A12 / A12X / A12Z | 8-core | iPad 8, iPad mini 5, iPad Air 3, iPad Pro 11 (1st, 2nd), 12.9 (3rd, 4th) | 3-6 GB |
| A13 | 8-core | iPhone 11 family, SE 2, iPad 9 | 3-4 GB |
| A14 | 16-core | iPhone 12 family, iPad 10, iPad Air 4 | 4 GB (12 Pro: 6 GB) |
| A15 | 16-core | iPhone 13 family, SE 3, iPhone 14/14 Plus, iPad mini 6 | 4-6 GB |
| A16 and later, M1 and later | 16-core | everything newer | 6 GB+ |

### 2. The speech engines

**SpeechTranscriber (what Seal uses now)**
- Apple's documentation: `isAvailable` is "A Boolean value that indicates whether this module is available given the
  device's hardware and capabilities", and the class page says: "Use the isAvailable or supportedLocales properties
  to see if the current device supports the speech-to-text models used by SpeechTranscriber. If it does not, consider
  disabling the feature or using DictationTranscriber instead." [Apple, developer documentation, fetched 2026-10-09]
- WWDC25 session 277: SpeechTranscriber "is available for all platforms but watchOS with certain hardware
  requirements." [Apple, June 2025]
- Apple's forum answer (thread 801197, accepted answer, Sept 2025): "There are hardware requirements for using
  SpeechTranscriber. The A16 iPads meet those requirements. For older hardware, you can use DictationTranscriber."
  The asker's iPad Pro 11-inch (2nd gen, A12Z) reported unavailable; an iPhone 16 Pro Max reported available.
  [Apple, forum; the poster is shown as "Apple_Agent" with an accepted answer]
- Developer test matrix (thread 806765, Nov 2025): `isAvailable == false` on iPhone 11, 11 Pro, 11 Pro Max and SE 2;
  true on iPhone 12 through 17 series. The poster's theory is that 8-core Neural Engines fail and 16-core ones pass.
  [Anecdotal]
- Thread 807739 (late 2025): SE 2 unsupported; iPhone 12, SE 3, 14 Pro and 15 Pro supported. [Anecdotal]
- Not available in the Simulator. [Anecdotal, several threads]
- Intel Macs: no direct test found. Apple's own Notes audio transcription is "M1 or later" [Apple Community thread
  quoting Apple]; a third-party dictation app says SpeechAnalyzer runs only on Apple silicon [Anecdotal].
- Seal already checks this at launch (`SpeechSupport.check`, re-checked every launch, never cached) and shows the
  unsupported screen (#80, "Check the device can run the speech engine"; closed). [Repo]

**DictationTranscriber (the backup engine)**
- Apple's documentation: "A speech-to-text transcription module that's similar to system dictation features and
  compatible with older devices. This transcriber uses the same speech-to-text machine learning models as system
  dictation features do, or as SFSpeechRecognizer does when it is configured for on-device operation. This
  transcriber does not support languages or locales that SFSpeechRecognizer only supports via network access."
  [Apple, fetched 2026-10-09] Fully on-device, then.
- WWDC25 session 277: "If you need an unsupported language or device, we also offer a second transcriber class:
  DictationTranscriber. It supports the same languages, speech-to-text model, and devices as iOS 10's on-device
  SFSpeechRecognizer but improving on SFSpeechRecognizer, you will NOT need to tell your users to go into Settings
  and turn on Siri or keyboard dictation for any particular language." [Apple]. In practice that means every iOS 26
  device.
- Same plumbing as SpeechTranscriber [Apple, documentation]: it is a `SpeechAnalyzer` module; its locale and asset
  calls are the same (`supportedLocales`, `installedLocales`, `supportedLocale(equivalentTo:)`), and its `Result` has
  the same members (`text`, `range`, `isFinal`, `alternatives`, `resultsFinalizationTime`). It supports
  `volatileResults` (live, still-changing captions), `frequentFinalization`, and the `audioTimeRange` attribute that
  Seal uses to line captions up with speaker turns. It has **no `isAvailable`**, because it runs everywhere, and **no
  `fastResults`** (`frequentFinalization` is the nearest equivalent). It adds content hints SpeechTranscriber
  lacks, including `farField` ("audio should be processed as if it were from a speaker far from the microphone"),
  which fits Seal's table setting.
- What the change looks like in Seal [Repo + Inferred]: `TranscriptionEngine` builds a `SpeechTranscriber` in two
  places and reads `transcriber.results` in two places. A fallback means choosing the module from
  `SpeechSupport.check` and making the result loop generic over the result type (both conform to
  `SpeechModuleResult`). `SpeechSupport` gets a third outcome ("supported via dictation engine") instead of
  `unsupportedDevice`. Estimate: about a day of code and tests, plus real-device checks on one tier-2 device.
- Quality and latency: Apple publishes no head-to-head numbers. Apple's framing: the old model "worked well for
  short-form dictation", while the new one is "good for long-form and distant audio, such as lectures, meetings, and
  conversations" and "both faster and more flexible" [Apple, WWDC25 277]. One independent Mac test put the old
  on-device engine (SFSpeechRecognizer, the same model DictationTranscriber uses) at about 9% word error on clean
  read speech, against about 2% for SpeechAnalyzer [Anecdotal, single blog test, Mac, clean audio; not
  restaurant-like]. Expect visibly more mistakes at a noisy table on tier 2. That's still far better than nothing,
  but marketing must never promise tier-2 accuracy.

**SFSpeechRecognizer with `requiresOnDeviceRecognition` (not recommended)**
- Same model as DictationTranscriber [Apple, above], with an older API. Apple's documentation: "on-device requests
  won't be as accurate", and the setting is only honored if `supportsOnDeviceRecognition` is true; otherwise the
  recognizer needs the network [Apple].
- The 1-minute cap: Apple's WWDC19 "Advances in Speech Recognition" slide lists the one-minute limit under server
  recognition, not on-device [Apple, 2019]. One developer report says on-device still stopped near a minute
  [Anecdotal, conflicting]. Either way, DictationTranscriber gives the same model with no cap concerns and no
  "turn on Siri/Dictation" dependency, so there's no reason to use SFSpeechRecognizer as the fallback.

### 3. The speaker model (FluidAudio Sortformer) on older chips

- What Seal ships: `fastV2_1`, fp16, about 241 MB on disk, loaded with `computeUnits = .all` (Neural Engine first)
  from the app bundle [Repo, ADR 0014, `LiveDiarizer.swift`]. FluidAudio documents this variant's output latency as
  about 1.04 s: the model needs about 1 s of audio before it can label it, then updates every 480 ms [Anecdotal:
  FluidAudio's own docs, v0.17.5, Oct 2026]. That delay is built in and is the same on every device. Seal already shows
  captions without waiting for a label (`speaker` is nil until the diarizer overlaps) [Repo].
- FluidAudio's own benchmarks are Mac-only: streaming Sortformer about 127x faster than real time on an M2;
  offline about 1,000-2,900x on an M5 Pro [FluidAudio Benchmarks.md]. **No iPhone or A-series numbers are
  published.** [Anecdotal: absence confirmed by reading the docs]
- Older-device notes from FluidAudio [FluidAudio docs + issue #726, June-Sept 2026; Anecdotal but from the library
  maintainers]: the large *high-context* fp16 variant (about 2.4 GB in memory) hangs for minutes compiling for the
  Neural Engine on an A14 iPhone with about 4 GB of memory, so FluidAudio switches that variant to CPU on devices
  under 8 GB. **Seal's fast variant is not affected by that rule.** FluidAudio offers a smaller `.palettized` build
  (6-bit) for "RAM-constrained / older devices", at about 0.9 points worse diarization error. A developer in #726
  says local model loading "forces .all", which is slow to load on A14. A separate A12 report (#979, Kokoro, a
  different model) hit the memory limit.
- What we don't know and must measure [Inferred]: per-update speaker-model time and first-load compile time on
  A13/A14/A15 with 3-4 GB of memory. The model is small next to the high-context one, and a 480 ms update has a
  lot of slack, so tier-1 phones are likely fine. A13 (tier 2) is the real unknown.
- No "CPU fallback" is needed as a separate product feature: Core ML falls back to the GPU or CPU on its own when
  the Neural Engine can't run a layer. The risk is speed, not a crash, which is why the per-session self-check
  (recommendation 3) is the right guard.
- If a 4 GB tier-1 device shows memory pressure, the fix is the palettized build for that device class, which
  means bundling a second model (about 97 MB, ADR 0014) or switching everyone to palettized. That is a decision
  for after the device-2 test, not now.
- ADR 0015's budget compares against a baseline measured on one device (currently an M1 Mac; iPhone pending) [Repo].
  It can't say whether an iPhone 12 is "fast enough"; it only catches regressions. Hence recommendation 5.
- Sound labels (`SNClassifySoundRequest`, `.version1`) are Apple's built-in classifier, available on every
  iOS 26 device and light. No tiering is needed for them. [Apple: SoundAnalysis, iOS 15+ for the built-in
  classifier; Repo]

### 4. App Store: declaring requirements, and what reviewers see

- `UIRequiredDeviceCapabilities` values available today [Apple, documentation fetched 2026-10-09] include
  `iphone-ipad-minimum-performance-a12` (A12 and later; useless here, since every iOS 26 device already has A12 or
  newer) and `iphone-performance-gaming-tier` ("graphics performance and gaming features equivalent to the iPhone 15
  Pro"). **There is no capability for "Neural Engine generation", A14, or speech support.**
- `iphone-performance-gaming-tier` also limits iPads to M1 and later, and developers report iPadOS then treats the
  app as a game (Game Mode overlay) [Anecdotal, forum threads 773898, 797023, 2025]. It would exclude the iPhone 12, 13 and 14 families
  and the iPhone 15 and 15 Plus, all of which run Seal fully. Not a fit.
- Adding a capability in a later update is refused at upload if it would drop devices the current version supports
  [Apple, QA1623: "you can't add UIRequiredDeviceCapabilities restrictions after an app is in the store"; archived
  2012 note, still matched by 2025 forum reports of the same upload error]. Raising the minimum OS is the allowed way to narrow
  support. So **v1's choice is effectively permanent**: no key now means the in-app check is the gate forever.
- App Review [Apple, guidelines]: 2.4.1 says "iPhone apps should run on iPad whenever possible", so dropping the iPad
  family doesn't keep Seal off reviewers' iPads (an iPhone-only app still runs on iPad). 2.1 rejects "obvious
  technical problems". A clear "this device can't run Seal's captions" screen is a working state, not a blank one.
  This is the risk-1 fix in `app-review-risks.md`, and #80 has built it.
- The store can't list "iPhone 12 or later" in the compatibility box; it only shows the minimum OS. The requirement
  goes in the description and the App Review notes (the notes text is already drafted in `app-review-risks.md`;
  update "A16-class or newer on iPad" to "A14 or newer" once device 4 or a tier-1 iPad confirms it).
- Mac (later): an Apple-silicon-only build is not offered to Intel Macs [Inferred from how the Mac App Store handles
  arm64-only binaries; confirm when the Mac target is set up].

### 5. Matrix rationale

- Tier 1 boundary = SpeechTranscriber available. Confirmed iPhones: 12-17 series, SE 3 [Anecdotal, two threads].
  Confirmed iPads: A16 [Apple]. A14/A15 iPads (iPad 10, Air 4, mini 6) are [Inferred] from the iPhones with the
  same chips. M-series iPads are [Inferred] from the Apple answer plus the 16-core pattern.
- Tier 2 = iOS 26 device without SpeechTranscriber. Every one of them is A12/A13 with an 8-core Neural Engine
  [Inferred pattern, consistent with every report found].
- Speaker labels on tier 2 are conditional because there are no A12/A13 numbers anywhere.

---

## Evidence entries (to merge into docs/research/evidence-log.md)

## E9. Which devices run iOS 26, iPadOS 26, iOS 27, iPadOS 27 and macOS 26
- **Source:** Apple Support, [How to download iOS 26](https://support.apple.com/en-us/123705) (updated 2026-09-16),
  [How to download iPadOS 26](https://support.apple.com/en-us/123706) (2025-09-17),
  [macOS Tahoe is compatible with these computers](https://support.apple.com/en-us/122867); press for the 27
  releases: [9to5Mac iOS 27 list](https://9to5mac.com/2026/06/08/ios-27-here-are-all-the-compatible-iphone-models/),
  [EveryMac iPadOS 27](https://everymac.com/systems/apple/ipad/ipad-faq/ipados-27-supported-devices-ipad-system-requirements.html),
  [9to5Mac macOS 27 drops four Macs](https://9to5mac.com/2026/05/18/macos-27-will-drop-support-for-these-four-mac-models/).
- **What we took:** iOS 26 and 27 both run on iPhone 11 / SE 2 and later; iPadOS 27 drops five A12-class iPads that
  stay installable on iPadOS 26; macOS 27 is Apple silicon only.
- **Confidence:** Strong for the 26 lists (Apple); Moderate for the 27 lists (consistent press reports of Apple's list).
- **Drives:** tier 4 ("can't install") in docs/research/device-compatibility.md; Mac build Apple-silicon-only.
- **Public use:** Yes.

## E10. Apple's new speech engine needs newer hardware than iOS 26
- **Source:** Apple, [SpeechTranscriber documentation](https://developer.apple.com/documentation/speech/speechtranscriber)
  and [isAvailable](https://developer.apple.com/documentation/speech/speechtranscriber/isavailable);
  [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/); Apple's forum answer
  [801197](https://developer.apple.com/forums/thread/801197) (Sept 2025).
- **What we took:** availability depends on hardware; A16 iPads qualify; older hardware should use
  DictationTranscriber or disable the feature. Apple publishes no device list.
- **Confidence:** Strong (Apple), but incomplete: no list.
- **Drives:** #80 (device check / unsupported screen); tiers 1-3.
- **Public use:** Careful ("needs a recent iPhone or iPad"; don't quote a device list as Apple's).

## E11. Developer reports: iPhone 11 and SE 2 can't run it, iPhone 12 and later can
- **Source:** Apple Developer Forums [806765](https://developer.apple.com/forums/thread/806765) (Nov 2025) and
  [807739](https://developer.apple.com/forums/thread/807739) (late 2025).
- **What we took:** `isAvailable` false on iPhone 11, 11 Pro, 11 Pro Max, SE 2 (and the iPad Pro 2nd gen in 801197);
  true on iPhone 12-17 and SE 3. Pattern: 8-core Neural Engine fails, 16-core passes (a developer's theory, matches
  every report).
- **Confidence:** Moderate (several consistent reports; not Apple).
- **Drives:** the tier-1/tier-2 line, the store description wording, test devices 2-4.
- **Public use:** Careful.

## E12. The backup engine for older devices: DictationTranscriber
- **Source:** Apple, [DictationTranscriber documentation](https://developer.apple.com/documentation/speech/dictationtranscriber),
  [Preset table](https://developer.apple.com/documentation/speech/dictationtranscriber/preset),
  [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/).
- **What we took:** on-device, works on the same devices as on-device SFSpeechRecognizer, no Siri/Dictation setting
  needed, same SpeechAnalyzer plumbing and result shape, live volatile results and audio time ranges supported, and a
  `farField` hint. Apple describes the old model as built for short dictation and the new one for distant,
  conversational audio, so tier 2 will be less accurate at a table.
- **Confidence:** Strong for capability (Apple); Weak for the size of the accuracy gap (one Mac blog test,
  [rohitraj.tech](https://rohitraj.tech/notes/apple-speechanalyzer-vs-whisper-on-device-stt-2026)).
- **Drives:** decision `fallback-engine` (v1 vs 1.1); tier 2.
- **Public use:** Careful ("older devices use Apple's dictation engine; captions are less accurate in noisy rooms").

## E13. SFSpeechRecognizer is not a better fallback
- **Source:** Apple, [requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition),
  [supportsOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition);
  [WWDC19 session 256 slides](https://devstreaming-cdn.apple.com/videos/wwdc/2019/256p7m9z4yst71ai/256/256_advances_in_speech_recognition.pdf);
  conflicting developer report on dev.to (2025).
- **What we took:** same model as DictationTranscriber, older API; the 1-minute cap is documented for server
  recognition, and one report says on-device also stops near a minute. No advantage over DictationTranscriber.
- **Confidence:** Strong (Apple) for "same model"; Weak on the on-device cap.
- **Drives:** fallback uses DictationTranscriber, never SFSpeechRecognizer (keeps ADR 0001's reasoning).
- **Public use:** Internal.

## E14. The speaker model on older chips: no published phone numbers
- **Source:** FluidAudio v0.17.5 docs, `Documentation/Diarization/Sortformer.md` and `Documentation/Benchmarks.md`
  ([GitHub](https://github.com/FluidInference/FluidAudio)); issue
  [#726](https://github.com/FluidInference/FluidAudio/issues/726) (June-Sept 2026); `recommendedComputeUnits(for:)`
  in `SortformerModelInference.swift`.
- **What we took:** the fast v2.1 variant has about 1.04 s of built-in output latency (480 ms updates); benchmarks
  are Mac-only (about 127x real time on M2); the large high-context fp16 head hangs compiling on 4 GB A14 phones (not
  Seal's variant); a palettized build exists for RAM-limited devices at about +0.9 points DER.
- **Confidence:** Moderate (library maintainers' docs; no independent phone measurements).
- **Drives:** the per-session speed self-check, test device 2, the per-tier latency baselines (ADR 0015).
- **Public use:** Internal.

## E15. App Store device restrictions can't express "A14 or newer"
- **Source:** Apple, [UIRequiredDeviceCapabilities](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequireddevicecapabilities)
  (fetched 2026-10-09); forum threads [773898](https://developer.apple.com/forums/thread/773898) and
  [797023](https://developer.apple.com/forums/thread/797023) (2025) on the gaming tier; Apple
  [QA1623](https://developer.apple.com/library/archive/qa/qa1623/_index.html) (archived, 2012); App Review Guidelines
  [2.1 and 2.4.1](https://developer.apple.com/app-store/review/guidelines/).
- **What we took:** the only modern performance key is the iPhone 15 Pro gaming tier (also M1-only on iPad, with a
  Game Mode side effect); keys can't be added in later updates if they drop devices; iPhone apps are expected to run
  on iPad, so reviewers can still test on one.
- **Confidence:** Strong (Apple) for the key list, the update rule and the guidelines; Moderate for the gaming-tier
  iPad behavior (forums).
- **Drives:** decision `store-restriction`; description wording; App Review notes.
- **Public use:** Internal.

## Decisions
<!-- marvin:decisions -->
### older-devices-v1: What should iPhone 11, iPhone SE (2nd gen) and A12/A13 iPads get in v1 (25 Oct)?
- [ ] The plain "Seal can't run on this device" screen, as built today (recommended)
- [ ] Captions from the backup engine (DictationTranscriber), built before submission
- [ ] Nothing extra: also remove iPad from v1 so fewer older devices can install it

### fallback-engine: When do we build the backup engine (tier 2)?
- [ ] First update after launch (1.1) (recommended)
- [ ] Later, only if testers or users with older devices ask
- [ ] Never: older devices stay "can't run"

### fallback-speaker-labels: On backup-engine devices, do speaker labels run?
- [ ] Only if the device passes a speed check at the start of each conversation; otherwise off, captions untouched (recommended)
- [ ] Always off on those devices
- [ ] Always on, accept possible lag

### store-restriction: How do we state the minimum device on the App Store?
- [ ] Description and review notes only: "Full captions need iPhone 12 or later, or an iPad with an A14 chip or later", with the in-app check as the gate (recommended)
- [ ] Add the iphone-performance-gaming-tier key (iPhone 15 Pro and later, M1 iPads only; excludes iPhone 12 to 14 and the standard iPhone 15, and sets off Game Mode on iPad)

### four-gb-model: If the iPhone 12/13 mini/SE 3 test shows memory pressure, what do we do?
- [ ] Ship the smaller palettized speaker model on 4 GB devices only (adds about 97 MB to the app)
- [ ] Switch every device to the palettized model (smaller app, slightly worse speaker separation)
- [ ] Turn speaker labels off on 4 GB devices

### test-devices: Which devices do we borrow before submission?
- [ ] iPhone 12 / 13 mini / SE 3 (tier-1 floor) plus iPhone 11 or SE 2, plus an iPad 9th gen (recommended)
- [ ] Only the tier-1 floor phone; rely on the unit tests for the "can't run" screen
- [ ] Ask recruited testers which phones they have first, then decide

### mac-scope: When the Mac app comes, which Macs?
- [ ] Apple silicon only; Intel Macs never see it (recommended)
- [ ] Also try Intel Macs on macOS 26 with the backup engine
