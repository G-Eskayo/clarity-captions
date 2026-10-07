# Clarity Captions — Context Glossary

Domain terms only. No implementation details beyond naming the frameworks involved — see
`docs/adr/` for decisions and rationale. Superseded designs (own-voice filtering, voice
enrollment) are documented in their original ADRs, not carried here — this file reflects current
domain understanding only.

## Core concept

- **Caption stream**: the live, scrolling transcript shown on screen as people speak nearby. The
  app's entire reason to exist.
- **On-device only**: the whole captioning path — audio capture, transcription, and speaker-turn
  labeling — runs locally on the phone, with no network call in that path at runtime. One
  exception, stated precisely: `SpeechAnalyzer`'s language model asset is provisioned by the
  system and may require a one-time network fetch before first use (see [[0001]]) — the guarantee
  is zero network *after* that asset is installed, not literally zero network ever under any
  circumstance. The reference app this project exists to improve on (Otter) requires an ongoing
  live service connection to function at all; this app's failure mode is at most a one-time setup
  dependency, not a permanent one.
- **Generalized, no per-user training**: the app must behave identically for every install, out
  of the box, with no enrollment, training, or per-user model state of any kind before it reaches
  a device. Stated explicitly (2026-09-08) as a hard requirement, not just a nice-to-have — this
  is what ruled out the original own-voice-filtering design (which required per-user voice
  enrollment) in favor of speaker-turn labeling — see [[0008]].
- **Speaker-turn labeling**: distinguishing *who is currently speaking* in the caption stream
  (labeled generically, e.g. "Speaker 1" / "Speaker 2") without identifying *which specific
  person* that is. Needs no enrollment or per-user data — the chosen replacement for own-voice
  filtering, see [[0008]]. Speaker labels are not guaranteed stable across separate sessions.
- **Sound label**: a non-speech caption for a recognized ambient sound — a short, bracketed label
  like "[Doorbell]" or "[Laughter]" — added to the stream independently of speech captions and
  never replacing or hiding spoken text. Distinct from speaker-turn labeling (which identifies
  *who* is speaking) and not a safety alert or notification. See [[0016]].

## Transcription engine

- **SpeechAnalyzer / SpeechTranscriber**: Apple's iOS 26 on-device speech-to-text framework,
  successor to the older `SFSpeechRecognizer`. Runs the whole transcription pipeline locally, no
  1-minute session cap (the old API's dealbreaker for real conversations). The chosen
  transcription engine — see [[0001]].
- **FluidAudio**: the Apache-2.0, CoreML-native, Neural-Engine-optimized Swift library used for
  speaker diarization — identifying distinct speakers and their turns in live audio — which
  speaker-turn labeling is built on directly ([[0008]]). No enrollment or reference-embedding
  matching involved (that was the superseded own-voice-filtering design, [[0002]]).
- **Sortformer**: the bundled speaker-diarization model (v2.1, fp16, 241 MB, CC BY 4.0 license).
  Handles 2–4 distinct speakers reliably; maxes out at 4 due to architecture. Higher-capacity
  alternatives (LS-EEND) are available but not bundled pending real-world measurements on resource
  budgets and latency — see [[0017]].

## Caption display

- **Caption display settings**: user-controllable appearance of the live caption text —
  background color, text size (responsive to system Dynamic Type), text color, and font,
  independently adjustable. A core accessibility requirement, not a cosmetic nice-to-have — visual
  needs vary a lot person to person, and this app is meant to work for anyone with needs like the
  primary user's, not just her specifically.

## Product principles

- **Delight**: any moment the user interacts directly with app setup/configuration should feel
  playful and enjoyable rather than clinical, via fun icons/colors/copy — named explicitly because
  this kind of UI easily defaults to feeling like a lab test if it isn't deliberately designed
  against.

- **Dim, don't dismiss**: speech the app judges to be background (far, quiet, low confidence) is
  shown de-emphasized, never silently removed — a missed caption costs a deaf user far more than
  an extra one. See [[0012]].
- **Radical simplicity**: usable by an older person with no instructions — one obvious action,
  minimal buttons, no technical choices exposed. A hard constraint on every screen, not polish.
  See [[0013]].

## Caption states

- **Listening**: captioning is running and the app is working. Covers both "people are talking" and
  "no one is talking right now" — a quiet room is normal, not a problem. See [[0018]].
- **Can't hear**: captioning is running but the microphone picks up almost nothing for a while —
  usually something covering it. A fixable problem, named in plain words; not a failure. See [[0018]].
- **Captions stopped**: the engine actually stopped; the only state that needs a tap (Start again).
  Distinct from Can't hear (still running) and from the user pressing Stop. See [[0018]].

- **Idle stop**: captioning stops on its own after a stretch with no captioned speech (default 5
  minutes; 15, 30 or Never in Settings). A gentle pause, not a failure. The only behavior setting;
  every other setting is caption display. See [[0019]].

- **Saved conversation**: the transcript of one captioning session, saved automatically on the phone
  when captioning stops and deleted after 30 days. Never backed up or synced. Distinct from the live
  caption stream, which is what's on screen now. See [[0022]].

## Environments

- **Primary environments**: restaurants, the dinner table, and any sit-down conversation —
  phone on or near a table, a few people, steady room noise, turn-taking with some overlap. The
  first user's actual use of her current tool. Far-field "across the room" is secondary. See
  [[0012]].

## People

- **Primary user**: whoever has enrolled/set up a given install of the app as its owner — a role,
  not a hardcoded identity. For this project's origin and first real installation, that's Gil's
  mother (deaf, already owns an iPhone 17), but nothing in the app's design should assume it's
  specifically her — see [[0007]]'s "built for everyone" decision.
