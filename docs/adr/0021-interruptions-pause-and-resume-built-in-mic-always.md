# 0021 — Interruptions pause and resume on their own; the iPhone's built-in mic is always the input

## Status

Accepted (2026-10-06), from the #3 design session.

## Context

Three interruptions are common in real use: a phone or FaceTime call takes the microphone; Siri, a
voice memo or another app grabs it; and a Bluetooth device connecting can make iOS switch the input to
that device's microphone. The primary user has a cochlear implant streamer that pairs with her
iPhone, so the third case is concrete, not hypothetical: an input on her head instead of on the table
would break the design every other decision rests on (the phone on the table listens to the room,
[[0012]]).

Requiring a tap to recover from every interruption conflicts with [[0013]].

## Decision

1. **Calls and other apps taking the mic**: captioning pauses with a plain reason (*Captions paused for
   your call*), keeps the transcript, and resumes automatically when the mic is free, marking the gap in
   the transcript. If the mic is not back within about 30 seconds, the state becomes **Captions
   stopped** ([[0018]]) with Start again.
2. **Input routing**: captioning always uses the iPhone's built-in microphone, whatever Bluetooth audio
   device connects (AirPods, hearing aids, cochlear implant streamers). Audio output routing is left
   to the system; the app plays no audio.

## Consequences

- No tap needed after a call or Siri; the conversation picks up where it was.
- Her streamer can stay connected for listening while the phone captions the table.
- Must be verified with her actual streamer: some hearing devices change the audio session in ways the
  simulator and AirPods won't show. Added to the usability test (#15).
- A remote table microphone (some implant systems sell one) as an input is a possible future idea,
  deliberately not in scope: it adds a choice [[0013]] forbids without evidence it's needed.
