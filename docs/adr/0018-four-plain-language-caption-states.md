# 0018 — Four plain-language states separate a quiet room from a real problem

## Status

Accepted (2026-10-06), from the #3 design session. Implemented by #9.

## Context

[[0013]] requires that a frozen screen never look like a crash. The app had only **Listening** and
**Stopped**, so a quiet room looked the same as a dead microphone, and a covered mic looked the same
as nobody talking. For a deaf user, a silent screen is ambiguous in a way it isn't for a hearing user:
she can't tell from the room whether anyone is speaking.

The app already measures the live audio level, which is enough to tell "room sound but no speech"
from "almost no sound at all".

## Decision

While captioning, the main screen shows one of four states, with this exact wording:

| Situation | Headline | Second line |
|---|---|---|
| Speech in the last few seconds | **Listening** | — |
| No speech for about 10 s, room sound present | **Listening** | *No one is talking right now* |
| Almost no sound for about 10 s | **I can't hear anything** | *Is something covering the microphone?* |
| The engine stopped | **Captions stopped** | a plain reason, e.g. *Another app is using the microphone* |

A small dot pulses with the room level in both Listening states (proof of life), is flat and amber in
"I can't hear anything", and "Captions stopped" shows one large **Start again** button. Only the
stopped state needs a tap. Technical error text is never the headline.

## Consequences

- A quiet room reads as normal; a fixable problem (covered mic) is named in words she can act on.
- Thresholds (about 10 s; what counts as "almost no sound") need tuning against real recordings
  (#1's restaurant test) so the amber state doesn't fire in a hushed room.
- Replaces the earlier "Stopped" headline and "Try again" button wording.
