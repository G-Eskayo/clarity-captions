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

## Transcription engine

- **SpeechAnalyzer / SpeechTranscriber**: Apple's iOS 26 on-device speech-to-text framework,
  successor to the older `SFSpeechRecognizer`. Runs the whole transcription pipeline locally, no
  1-minute session cap (the old API's dealbreaker for real conversations). The chosen
  transcription engine — see [[0001]].
- **FluidAudio**: the Apache-2.0, CoreML-native, Neural-Engine-optimized Swift library used for
  speaker diarization — identifying distinct speakers and their turns in live audio — which
  speaker-turn labeling is built on directly ([[0008]]). No enrollment or reference-embedding
  matching involved (that was the superseded own-voice-filtering design, [[0002]]).

## Caption display

- **Caption display settings**: user-controllable appearance of the live caption text —
  background color, text size, text color, and font, independently adjustable. A core
  accessibility requirement, not a cosmetic nice-to-have — visual needs vary a lot person to
  person, and this app is meant to work for anyone with needs like the primary user's, not just her
  specifically.

## Product principles

- **Delight**: any moment the user interacts directly with app setup/configuration should feel
  playful and enjoyable rather than clinical, via fun icons/colors/copy — named explicitly because
  this kind of UI easily defaults to feeling like a lab test if it isn't deliberately designed
  against.

## People

- **Primary user**: whoever has enrolled/set up a given install of the app as its owner — a role,
  not a hardcoded identity. For this project's origin and first real installation, that's Gil's
  mother (deaf, already owns an iPhone 17), but nothing in the app's design should assume it's
  specifically her — see [[0007]]'s "built for everyone" decision.
